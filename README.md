# ai-interview-platform

A React frontend for an AI interview platform, taken from source code to a running workload on
Amazon EKS through a fully automated CI/CD pipeline — with **no AWS credentials stored anywhere**.

This repository is a learning project, and it is also a working system. The frontend builds, tests,
scans, deploys and serves over a public URL on every push to `main`.

> 📘 **New here?** Read [`RUNBOOK.html`](RUNBOOK.html) — a step-by-step guide that takes a blank AWS
> account and a fresh clone to a live deployment. It documents every phase, every checkpoint, and
> every failure you are likely to hit (and why).

---

## What this is, and what it is not

**It is:** the frontend, plus all the infrastructure, pipeline and platform code needed to run it.

**It is not:** a complete application. There is no backend or middleware service in this repository,
so login and API calls **fail by design** — nginx's SPA fallback answers `/api/*` with `index.html`.
That is a phase boundary, not a bug. See [Known limitations](#known-limitations--next-steps).

---

## Architecture

```
git push  →  GitHub Actions  →  build · test · scan  →  Docker image
                                                            │
                                                            ▼
                                                          ECR
                                                            │
                                                            ▼
                              kubectl apply  →  EKS pod (private subnet)
                                                            │
                                                            ▼
                                        Ingress  →  ALB  →  🌐 public URL
```

| Layer | Technology | Managed by |
|---|---|---|
| Network | VPC, 4 subnets across 2 AZs, IGW, NAT, route tables | **Terraform** (14 resources) |
| Cluster | Amazon EKS 1.36, 2× t3.small managed node group | **eksctl** |
| Registry | Amazon ECR | AWS |
| CI/CD | GitHub Actions — 4 jobs | YAML |
| Auth | GitHub OIDC → IAM role (keyless) | IAM |
| Ingress | AWS Load Balancer Controller + ALB | Helm |
| App | React 18, Vite 6, MUI, nginx | Docker |

### The two-tool split, and why it matters

Terraform builds the network. eksctl builds the cluster. **Neither knows the other exists**, and they
keep their state in different places:

| | Terraform | eksctl |
|---|---|---|
| State lives in | `terraform.tfstate` — a file on your laptop | AWS CloudFormation stacks |
| Delete with | `terraform destroy` | `eksctl delete cluster` |
| Cleans up the other's resources? | No | No |

The cluster sits *inside* the VPC, so **teardown order is fixed**: delete the cluster first, then
destroy the VPC. Reverse it and the VPC destroy fails with `DependencyViolation`.

---

## Repository layout

```
src/                        React application — pages, components, API client, auth
src/test/                   Vitest unit tests
k8s/                        Deployment, Service, ConfigMap, Ingress
Terraform/                  VPC as code (14 resources)
.github/workflows/           The pipeline
Dockerfile                  Two-stage build: Node compiles, nginx serves
docker-entrypoint.sh        Renders runtime config at container start
nginx.conf                  Unprivileged server on port 3000, JSON logs, cache rules
RUNBOOK.html                Full build guide, zero → live
sonar-project.properties    SonarCloud project config
```

---

## Running it locally

```bash
npm ci                  # install exactly what the lockfile says
npm run dev             # http://localhost:5173
```

Run the same checks CI runs, before you push:

```bash
npm run lint            # eslint, --max-warnings 0
npm run test            # unit tests
npm run test:coverage   # tests + coverage/lcov.info
npm run build           # produces dist/
```

Build and run the real image:

```bash
docker build -t frontend:local .
docker run --rm -p 3000:3000 -e API_BASE_URL="" -e APP_ENV=dev frontend:local
curl -i http://localhost:3000/healthz
```

---

## The CI/CD pipeline

Four jobs. Three run in parallel and check different things; the fourth only starts if all three
passed, and only on `main`.

| Job | Does | Fails the run when |
|---|---|---|
| `app` | `npm ci` → lint → test with coverage → build → SonarCloud scan | any warning, any failing test, or a failed quality gate |
| `secrets` | Gitleaks over the **full git history** | it finds anything shaped like a credential |
| `manifests` | kubeconform `-strict` on `k8s/*.yaml` | an unknown or misspelled manifest field |
| `deploy` | OIDC → Trivy scan → ECR push → `kubectl apply` → verify → rollback on failure | the rollout stalls or the smoke test fails |

### Keyless authentication

No AWS access key exists in this repository, in GitHub secrets, or in the image. GitHub issues a
short-lived signed OIDC token; AWS verifies it against the registered provider and the role's trust
policy, then returns credentials that expire within the hour.

The workflow requests a token with exactly one permission, on one job:

```yaml
permissions:
  contents: read        # workflow default

jobs:
  deploy:
    permissions:
      contents: read
      id-token: write   # ← only this job can request an OIDC token
```

The AWS-side trust policy pins the exact repository **and** branch using GitHub's immutable subject
IDs, so it survives a repo rename and cannot be satisfied from a fork.

### Security gates

| Gate | Catches | Blocking mechanism |
|---|---|---|
| Gitleaks | committed secrets, anywhere in history | non-zero exit |
| ESLint | bad patterns, unused code | `--max-warnings 0` |
| Vitest | behaviour regressions | any failing test |
| SonarCloud | bugs, smells, duplication, coverage trend | quality gate |
| kubeconform | invalid Kubernetes YAML | `-strict` |
| Trivy | CRITICAL CVEs in the built image | `exit-code: '1'` |

A scanner without a blocking exit code is decoration, not a gate — every one of these is wired to
actually stop the run.

---

## Infrastructure

### Terraform — the VPC

```bash
cd Terraform
terraform init && terraform plan     # expect: 14 to add
terraform apply
terraform output                     # copy these IDs — you need them next
```

Creates a VPC (`10.0.0.0/16`) with two public and two private subnets across `ap-south-1a` and
`ap-south-1b`, an Internet Gateway, a NAT Gateway, and the route tables that connect them.

`enable_dns_hostnames` and `enable_dns_support` are both required — without them EKS nodes register
but never join.

### eksctl — the cluster

```bash
eksctl create cluster \
  --name ai-interview-platform-eks --region ap-south-1 --version 1.36 \
  --vpc-private-subnets=$PVT1,$PVT2 --vpc-public-subnets=$PUB1,$PUB2 \
  --nodegroup-name default --node-type t3.small \
  --nodes 2 --nodes-min 2 --nodes-max 3 \
  --node-private-networking --managed --with-oidc
```

Nodes run in the **private** subnets and reach the internet outbound through the NAT gateway, so they
have no public IP. `--with-oidc` registers the cluster's OIDC issuer in IAM, which is what makes IRSA
work later.

> ⚠️ **`eksctl` is safe to walk away from but not to cancel.** It prints
> `waiting for CloudFormation stack` every 30 seconds with no spinner. That is progress. `Ctrl+C`
> kills only your local watcher — AWS keeps building, and you are left without a kubeconfig.

### Manual steps that are not yet automated

Two things must be redone on every rebuild. Both are candidates for Terraform:

1. **Subnet tagging** — the load balancer controller discovers subnets by tag, not by being told:

   ```bash
   aws ec2 create-tags --resources $PUB1 $PUB2 --tags Key=kubernetes.io/role/elb,Value=1
   aws ec2 create-tags --resources $PVT1 $PVT2 --tags Key=kubernetes.io/role/internal-elb,Value=1
   aws ec2 create-tags --resources $PUB1 $PUB2 $PVT1 $PVT2 \
     --tags Key=kubernetes.io/cluster/ai-interview-platform-eks,Value=shared
   ```

   > These cannot live in `vpc.tf` today: the subnets carry
   > `lifecycle { ignore_changes = [tags] }`, which makes Terraform silently discard any tag.
   > Remove those blocks first.

2. **Cluster access entries** — a new cluster starts with an empty access list:

   ```bash
   aws eks create-access-entry --cluster-name ai-interview-platform-eks \
     --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/role-ai-interview-platform
   aws eks associate-access-policy --cluster-name ai-interview-platform-eks \
     --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/role-ai-interview-platform \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
     --access-scope type=cluster
   ```

### Ingress — the public URL

```bash
kubectl apply -f k8s/alb-ingress.yml -n default
kubectl get ingress -n default -w      # ADDRESS fills in after 2–3 min, then wait 1–2 more
```

The controller discovers the tagged public subnets, builds an ALB across **two AZs**, and registers
the pod's private IP as a target (`target-type: ip`). The only thing pointing it at your subnets is
the `kubernetes.io/role/elb=1` tag.

---

## Cost

| Resource | Rate | Notes |
|---|---|---|
| EKS control plane | **$0.10/hr** | Billed even with **zero nodes** |
| 2× t3.small nodes | ~$0.042/hr | Only while running |
| NAT gateway | **$0.062/hr** | 24/7, no traffic required |
| ALB | ~$0.0225/hr | + LCU. Exists only while the Ingress does |
| ECR | ~₹0 | Free tier covers it |

**Full stack: ~$0.22/hr ≈ ₹450/day.**

This project is built to be torn down. Verify the teardown every time:

```bash
aws ec2 describe-vpcs         --query "Vpcs[].[VpcId,IsDefault]" --output table
aws ec2 describe-nat-gateways --query "NatGateways[].State"      --output table
aws eks list-clusters --region ap-south-1
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName"
```

---

## Lessons learned

The failures here are more instructive than the successes. A few that cost real time:

- **AWS IAM ≠ Kubernetes RBAC.** A role with `AdministratorAccess` still cannot run
  `kubectl get pods` — EKS checks its own access-entry list, not IAM. `Unauthorized` means no entry;
  `Forbidden` means the entry exists but the policy is too narrow.
- **A trust policy has a specific `sub` form.** A job that declares `environment:` gets
  `repo:OWNER/REPO:environment:production`; a job without one gets `…:ref:refs/heads/main`. Copy the
  wrong form and every deploy fails with no explanation.
- **Silent failures are the default in EKS.** A missing subnet tag produces no load balancer *and no
  error*. A missing ServiceAccount annotation produces a controller that looks healthy and fails
  every AWS call. Hence the checkpoints.
- **`eksctl delete cluster` only cleans up if it can find the cluster.** A 404 aborts the command
  *before* its cleanup phase, orphaning CloudFormation stacks and security groups.
- **Your terminal is a window, not a switch.** Ctrl+C, a client timeout, and a console button do not
  stop AWS. When something looks stuck, run a `describe` — never a cancel.
- **Scanner exit codes are the whole gate.** Trivy without `exit-code: '1'` prints a table and
  passes. So does SonarCloud without `qualitygate.wait`.
- **`git add .` is relative to your cwd**, not the repo root. And a `.gitignore` negation cannot
  re-include a file inside an ignored *directory* — use `Progress/*` rather than `Progress/`.

---

## Known limitations & next steps

- [ ] **Frontend only.** No middleware or backend exists here, so login fails by design.
- [ ] **EKS is not in Terraform.** The cluster is eksctl-managed; `terraform destroy` does not know
      about it. Moving it into Terraform would also remove the two manual steps above.
- [ ] **No pod `securityContext`.** The Dockerfile runs non-root, but the Deployment does not
      enforce it.
- [ ] **`replicas: 1`.** A rolling update briefly takes the app down; a node failure takes it down
      until rescheduling.
- [ ] **No CPU limit** (memory has one).
- [ ] **`AdministratorAccess` on the CI role.** Far broader than the pipeline needs — should be
      narrowed to the ECR and EKS permissions it actually uses.
- [ ] **Terraform uses local state.** No S3 backend; one lost laptop means lost ownership.
- [ ] **HTTP only.** No ACM certificate or HTTPS listener on the ALB.

---

## Reference

- [`RUNBOOK.html`](RUNBOOK.html) — the complete zero-to-live guide, with diagrams and per-phase
  checkpoints
- [`k8s/`](k8s) — the four manifests
- [`Terraform/`](Terraform) — the VPC
- [`.github/workflows/pipeline.yml`](.github/workflows/pipeline.yml) — the pipeline

---

*Region `ap-south-1` · EKS 1.36 · Terraform · eksctl · GitHub Actions · AWS Load Balancer Controller*

## Day 1 — GitHub OIDC to AWS IAM Setup

Established keyless authentication from GitHub Actions to AWS using OpenID Connect.

### 1. GitHub CLI Auth
- Authenticated device via `gh auth login`.
- Created local project folder and initialized Git repo.
- Created GitHub repository and pushed initial code.

### 2. AWS IAM OIDC Provider
- Added OpenID Connect identity provider:
  - Provider URL: `https://token.actions.githubusercontent.com`
  - Audience: `sts.amazonaws.com`

### 3. AWS IAM Role for GitHub Actions
- Created IAM role with Web Identity trust for OIDC provider.
- Scoped trust to specific org/repo/branch:
  - `repo:<OWNER>/<REPO>:ref:refs/heads/<BRANCH>`
- Temporary admin policy for testing. To be replaced with least-privilege in production.

### 4. Test Pipeline
- Created `.github/workflows/pipeline.yml`:
  - Trigger: `push` to `main` and `workflow_dispatch`
  - Permissions: `id-token: write`, `contents: read`
  - Region configured via `AWS_REGION` env
  - Step uses `aws-actions/configure-aws-credentials@v4` with:
    - `role-to-assume: arn:aws:iam::<AWS_ACCOUNT_ID>:role/<ROLE_NAME>`
    - `aws-region: ${{ env.AWS_REGION }}`
- Pushed to `main` to verify Actions trigger and role assumption succeeds.

### 5. IDs and Trust Policy
- Retrieved GitHub repo ID via `https://api.github.com/repos/<OWNER>/<REPO>` (public repos only).
- Retrieved GitHub account/user ID via `https://api.github.com/users/<OWNER>`.
- Updated role trust relationship with above values.
- Updated workflow `role-to-assume` to new role ARN and re-pushed. Role assumption verified.


## Day 2 — Terraform VPC for EKS (Plan, Apply, Destroy)

Built and validated VPC foundation for future EKS cluster in `ap-south-1`.

### 1. Terraform Structure
- Reviewed `Terraform/vpc.tf` (not runnable alone).
- Created `Terraform/main.tf`: `terraform` block, `aws ~> 5.0`, `region = var.aws_region`.
- Created `Terraform/variables.tf`: VPC CIDR, 4x subnet CIDRs, names, `project`, `created_by`.
- Created `Terraform/outputs.tf`: VPC, subnet, IGW, NAT, route table IDs.
- Fixed invalid `var.pub_subnet_cidr-2` / `var.pvt_subnet_cidr-2` to `var.pub_subnet_cidr_2` / `var.pvt_subnet_cidr_2`.
- `terraform init -backend=false` + `terraform validate` passes.

### 2. IAM for Local Terraform
- No `IAM users` existed. Created user `terraform-local` (no console).
- Created group `terraform-vpc-admins` with `AmazonVPCFullAccess`.
- Created access key (CLI) -> `aws configure` (`ap-south-1`) -> `aws sts get-caller-identity`.
- Kept `role-ai-interview-platform` for GitHub OIDC; local OIDC reuse not possible without source identity.

### 3. Git Hygiene
- `.gitignore` only had `Progress/`. Added `Terraform/.terraform/`, `*.tfstate*`, `*.tfvars`, `tfplan`, `*.plan`, `file.txt`. Kept `.terraform.lock.hcl`.
- First push rejected: `terraform-provider-aws_v5.100.0_x5.exe` (628 MB) exceeds GitHub 100 MB limit.
- Fixed via `git rm -r --cached Terraform/.terraform`, `git commit --amend`, `git push origin main`.

### 4. Plan / Harden / Apply
- `terraform plan -out=tfplan`: 14 to add (1x `aws_vpc`, 4x `aws_subnet`, 1x `aws_internet_gateway`, 1x `aws_eip`, 1x `aws_nat_gateway`, 2x `aws_route_table`, 4x `aws_route_table_association`).
- Added `enable_dns_support` + `enable_dns_hostnames = true` to `aws_vpc.my-vpc`.
- Added `map_public_ip_on_launch = true` to public subnets.
- Added `Environment/Project/created_by` to route tables, IGW, EIP (`nat-eip`), NAT.
- Partial `apply` failed on `aws_eip.lb`: `UnauthorizedOperation` for `ec2:DescribeAddressesAttribute` (missing from `AmazonVPCFullAccess` with provider `5.100.0`). Added inline policy for `ec2:DescribeAddresses` + `ec2:DescribeAddressesAttribute`.

### 5. Cost Control / Destroy
- `terraform destroy`: 14 destroyed.
- Verified: `describe-vpcs` -> `[]`, `describe-subnets` -> `[]`, `describe-addresses` -> `[]`, `describe-nat-gateways` -> `State: deleted`.
- `terraform state list` empty. No NAT/EIP charges remain.


## Day 3 — Frontend container, EKS cluster, and full CI/CD

Took the React app from source to a running pod on EKS, deployed by the pipeline.

### 1. Containerising the frontend
- Wrote a multi-stage `Dockerfile`: Node 22 builds the bundle, nginx serves it. The final image
  contains no Node runtime, no `node_modules` and no source.
- Copied `package.json` + lockfile first so a source-only change reuses the cached dependency layer.
- Ran nginx as `USER 101:101` on port **3000** so no privileged-port capability is needed, and
  relocated every path nginx writes to (PID, temp dirs) under `/tmp`.
- Added `/healthz` — answers without touching the filesystem, excluded from access logs.
- Wrote `docker-entrypoint.sh` to render `runtime-config.js` at **container start** from environment
  variables, so one image promotes across environments unchanged. JS-escaped the values so a quote in
  a config value cannot break out of the string literal.

### 2. Runtime configuration instead of build-time
- Documented why the API URL is *not* baked in at build: doing so would mean one image per
  environment, defeating the point of promoting a tested artifact.
- `src/config.js` reads `window.__APP_CONFIG__`; `k8s/configmap.yaml` supplies `API_BASE_URL` and
  `APP_ENV`.
- Verified the chain end to end by curling `/runtime-config.js` from a port-forwarded pod.

### 3. EKS cluster
- Reviewed deployed-cluster requirements: `enable_dns_hostnames`/`enable_dns_support` (already set
  in Day 2), two AZs, working NAT for node egress.
- Discovered that eksctl's existing-VPC mode requires subnet tags (`role/elb`,
  `role/internal-elb`, `cluster/<name>`) and enforces `MapPublicIpOnLaunch` on public subnets —
  none of which are checked by EKS or eksctl themselves.
- Tagged all four subnets, then created the cluster with `--node-private-networking --managed
  --with-oidc`.
- Verified 2 nodes `Ready` in **different AZs**, both in private subnets with no public IP, and all
  eight `kube-system` pods `Running` with zero restarts.

### 4. ECR and the deploy job
- Created the ECR repository. **The name includes a slash** —
  `ai-interview-dev-platform/frontend` — because the workflow builds the image reference as
  `$REGISTRY/$ECR_REPO/frontend:$SHA`. Creating the prefix alone fails at push.
- Fixed the deploy job's `if:` condition: it checked `refs/heads/master` on a `main` repository, so
  the job was being silently skipped on every run.
- Tagged images with the commit SHA, never `latest`, so a running pod's image tag maps to an exact
  line of code.
- Added the `Verify` step — a throwaway `curlimages/curl` pod that fetches the Service from inside
  the cluster — and an automatic `kubectl rollout undo` on failure.

### 5. The access-entry lesson
- The deploy job failed with `Unauthorized` even though the role held `AdministratorAccess`.
- Root cause: **AWS IAM and Kubernetes RBAC are separate authorization systems.** EKS authenticates
  the AWS principal, then looks it up in its own access-entry list — which contained only the
  cluster creator, the node role and the AWS service role.
- Fixed with `create-access-entry` + `associate-access-policy`, scoped to the `default` namespace
  rather than the cluster.
- Noted the diagnostic split for future debugging: **`Unauthorized` = no entry,
  `Forbidden` = entry exists but policy too narrow.**

### 6. SonarCloud
- Two failures, both configuration rather than code:
  - `Not authorized or project not found` — `sonar-project.properties` still pointed at the tutorial
    author's organisation. The properties file **overrides the SonarCloud UI**, so binding the
    project in the browser was not enough.
  - `You are running CI analysis while Automatic Analysis is enabled` — SonarCloud had switched on
    server-side analysis at import time. Disabled it, because Automatic Analysis cannot produce code
    coverage, which is the entire reason the lcov report is configured.

### 7. Process mistakes worth recording
- Pressed `Ctrl+C` during `eksctl create cluster` while it was polling. This does not cancel the
  build — AWS kept going and the cluster finished. But eksctl never wrote the kubeconfig, so
  `kubectl` fell back to `localhost:8080`. Fixed with `aws eks update-kubeconfig`.
- Later let eksctl hit its own 25-minute timeout. That is client-side only; the cluster was still
  building. Checked real state with
  `aws eks describe-nodegroup --query 'nodegroup.health.issues'`.
- Merged two commands onto one line by losing a newline, producing a cluster name of
  `ai-interview-platform-ekskubectl`. A 30-second mistake that cost longer to diagnose.

### 8. Result
- Pipeline green end to end: lint, test with coverage, build, Sonar scan, GitLeaks, kubeconform,
  Trivy, ECR push, deploy, verify.
- Pod `1/1 Running` with zero restarts, serving the app over `kubectl port-forward`.
- Confirmed the runtime-config chain in the browser: the seed-account shortcuts are visible because
  `APP_ENV=dev` came through the ConfigMap.


## Day 4 — ALB Ingress and a public URL

Gave the app a real internet-facing address, and in doing so verified the last untested piece of the
infrastructure.

### 1. The controller needs an AWS identity (IRSA)
- Confirmed the cluster's OIDC issuer was already registered in IAM — `--with-oidc` on create had
  done it.
- Created the IAM policy from AWS's published document at the version matching the chart, with a
  `head -3` guard: `curl -sL` silently saves GitHub's 404 page as JSON if the version tag is wrong,
  and `create-policy` then fails complaining about the document rather than the URL.
- Created the role and ServiceAccount with `eksctl create iamserviceaccount`, which produces three
  objects across two systems: an IAM role, a **trust policy** naming
  `system:serviceaccount:kube-system:aws-load-balancer-controller`, and a Kubernetes ServiceAccount
  carrying the role ARN as an annotation.

### 2. Verified IRSA rather than assuming it
- The critical checkpoint: the ServiceAccount annotation must print a role ARN. A blank line means the
  controller starts, looks healthy, and fails every AWS call.
- After installing the chart, read the pod's environment and found `AWS_ROLE_ARN` and
  `AWS_WEB_IDENTITY_TOKEN_FILE` — **nothing in the Helm chart sets those.** A mutating webhook
  injected them because of the annotation. That is the whole mechanism, visible in one command.
- Confirmed the trust policy condition matched the live cluster issuer and the exact ServiceAccount.

### 3. The Ingress
- Used `target-type: ip` so the ALB registers pod IPs directly via the VPC CNI, rather than hopping
  through a NodePort on the host.
- Pointed `healthcheck-path` at `/healthz` — the endpoint already serving the Kubernetes probes.
- Kept the Ingress to a **single `/` rule**. Adding an `/api → middleware` path would reference a
  Service that does not exist, and the controller creates **nothing at all** when any referenced
  Service is missing.

### 4. Two waits, not one
- `ADDRESS` populated after ~2 minutes, but `curl` returned `000` immediately after. The ALB existed
  and was still provisioning — DNS had not propagated and no target had passed a health check yet.
- Also noted that `curl -s` hides the error message; `-sS` shows *why* it failed.

### 5. Verified from three independent angles
| Check | Result |
|---|---|
| `kubectl get ingress` | `frontend`, class `alb`, ADDRESS populated |
| Target group health | pod IP `10.0.12.x`, port 3000, `healthy` |
| EC2 console → Network mapping | ALB `active`, internet-facing, **two AZs**, subnets from `10.0.1.0/24` and `10.0.2.0/24` |
| Browser / `curl` from outside AWS | **HTTP 200** |

- The console view was the decisive one: the ALB spans two Availability Zones, which is only
  possible because **two** public subnets were tagged `kubernetes.io/role/elb=1`.
- This closed the last unverified item in the project. Nothing before this had exercised the subnet
  tags — `port-forward` bypasses AWS networking entirely.

### 6. Cost discipline
- The ALB adds ~$0.0225/hr (≈₹1,400/month), and it is **owned by the controller, not by AWS
  automation**. Uninstalling the controller while an Ingress still exists orphans the load balancer —
  invisible to the cluster, still billing.
- Teardown order is therefore: delete the **Ingress** first, verify the ALB is gone from AWS, then
  uninstall the controller, then delete the cluster, then `terraform destroy`.


## Day 5 — Documentation

- Wrote `RUNBOOK.html`: a complete zero-to-live guide for a new person with a new AWS account.
  Thirteen phases, each ending with a checkpoint command whose output says whether to continue.
- Included the failures, not just the happy path — the trust-policy subject form, the IAM/RBAC split,
  the silent subnet-tag failure, eksctl's interrupt and timeout behaviour, the CloudFormation and
  security-group cleanup traps, and both SonarCloud configuration errors.
- Added the diagrams, the cost model, a glossary, and a troubleshooting index.

