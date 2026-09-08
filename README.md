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

> Note: Sensitive values (AWS account IDs, role ARNs, GitHub IDs) are intentionally omitted. Use placeholders.
