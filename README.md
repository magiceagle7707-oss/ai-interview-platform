# ai-interview-platform

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

