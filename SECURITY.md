# QuantumRishi GitHub Security Guide

> Security configuration and best practices for the QuantumRishi organization

## Organization Setup

### Prerequisites Checklist

- [x] **Organization Created**: `QuantumRishi`
- [x] **Teams Configured**:
  - `devops` - Infrastructure & CI/CD management
  - `ai-team` - AI/ML development
  - `ml-team` - Machine learning specialists
  - `data-team` - Data engineering
  - `frontend-team` - Frontend/UI development
  - `security` - Security reviews & audits

### Repository Structure

| Repository | Purpose | Visibility |
|------------|---------|------------|
| `qr-pipeline` | Shared CI/CD workflows | Public |
| `qr-db` | Database schemas & migrations | Private |
| `qr-mail` | Centralized email API | Private |
| `qr-devops` | Infrastructure as Code | Private |
| `qr-infra` | Cloud infrastructure configs | Private |

## Security Configuration

### 1. Personal Access Token (PAT) Scopes

**Org-level CI/CD PAT** (minimal scopes):
```
✅ repo              - Full control of private repositories
✅ workflow          - Update GitHub Action workflows
✅ admin:repo_hook   - Full control of repository hooks
```

**Fine-grained PAT for Self-hosted Runners**:
```
✅ Repository: Read/Write
✅ Actions: Read/Write
✅ Secrets: Read
```

### 2. SSO & 2FA Enforcement

**Required Settings** (Organization → Settings → Security):

```yaml
Two-Factor Authentication: Required for all members
SSO Configuration:
  - Provider: GitHub (native)
  - Enforce for all members: Yes
  - Allow public members: No
```

### 3. SSH Deploy Keys

**Per-Repository Deploy Keys**:

| Repository | Key Name | Permissions |
|------------|----------|-------------|
| `qr-pipeline` | `ci-checkout` | Read-only |
| `qr-db` | `migration-runner` | Read-only |
| `qr-mail` | `deploy-key` | Read-only |

**Self-hosted Runner**:
- Uses fine-scoped PAT for push permissions
- SSH key stored in Vault with rotation policy

### 4. GitHub Actions Hardening

**Organization Settings** (Settings → Actions → General):

```yaml
Policies:
  - Allow GitHub Actions: Selected repositories only
  - Allow actions created by GitHub: Yes
  - Allow actions by Marketplace verified creators: Yes
  - Allow specified actions: Yes (allowlist below)

Fork pull request workflows:
  - Require approval for first-time contributors: Yes
  - Require approval for all outside collaborators: Yes

Workflow permissions:
  - Default: Read repository contents and packages permissions
  - Allow GitHub Actions to create and approve PRs: No (disabled)
```

**Allowed Actions (SHA-pinned)**:
```yaml
- actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332  # v4.1.7
- actions/setup-node@60ecd5dd545e0ff3b4a7ad3a7dcd866e9a06ee06  # v4.0.2
- pnpm/action-setup@fe02b34f77f8bc703788d5817da081398fad5dd2  # v4.0.0
- step-security/harden-runner@17d0e2bd7d51742c71671bd19fa12bdc9d40a3d6  # v2.8.1
- github/codeql-action/*@b611370bb5703a7efb587f9d136a52ea24c5c38c  # v3.25.11
- cloudflare/wrangler-action@f84a562284fc78278ff9052435d9f22f9c90c557  # v3.7.0
- supabase/setup-cli@1.3.0
- trufflesecurity/trufflehog@main
```

### 5. Branch Protection Rules

**Main Branch Protection** (apply to all repos):

```yaml
Protection Rules:
  - Require pull request before merging: Yes
  - Required approving reviews: 1 (2 for critical repos)
  - Dismiss stale PR approvals: Yes
  - Require review from code owners: Yes
  - Require status checks:
    - CI (lint, typecheck, test)
    - Security scan
  - Require conversation resolution: Yes
  - Require signed commits: Recommended
  - Include administrators: Yes
  - Restrict force pushes: Yes
  - Restrict deletions: Yes
```

### 6. Secrets Management

**Organization Secrets** (Settings → Secrets → Actions):

| Secret | Scope | Description |
|--------|-------|-------------|
| `VERCEL_TOKEN` | All repos | Vercel deployment token |
| `VERCEL_ORG_ID` | All repos | Vercel organization ID |
| `CLOUDFLARE_API_TOKEN` | All repos | Cloudflare API token |
| `CLOUDFLARE_ACCOUNT_ID` | All repos | Cloudflare account ID |
| `SUPABASE_ACCESS_TOKEN` | All repos | Supabase management API |
| `RESEND_API_KEY` | Selected repos | Resend email API |
| `NPM_TOKEN` | Selected repos | NPM publish token |

**Secret Rotation Policy**:
- API keys: Every 90 days
- Service account tokens: Every 30 days
- PATs: Every 60 days

### 7. Dependabot Configuration

**Enable for all repositories** (`.github/dependabot.yml`):

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "QuantumRishi/security"
    labels:
      - "dependencies"
      - "security"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    reviewers:
      - "QuantumRishi/devops"
```

### 8. Code Scanning (CodeQL)

**Enable Advanced Security** (Settings → Security → Code security and analysis):

```yaml
Dependency graph: Enabled
Dependabot alerts: Enabled
Dependabot security updates: Enabled
Code scanning: Enabled (CodeQL)
Secret scanning: Enabled
Push protection: Enabled
```

## MCP Server Integration

### GitHub MCP Binding

The GitHub MCP server provides Copilot Agents access to:

1. **Repository Management**: Create, update, delete repos
2. **Issue Tracking**: Create/manage issues across all QR repos
3. **Pull Requests**: Create PRs, request reviews, merge
4. **Actions**: Trigger workflows, view status
5. **Code Search**: Search across organization codebase

**Connected Repositories**:
- `qr-pipeline` (primary orchestrator workflows)
- `qr-db` (database context)
- `qr-mail` (email templates)
- All `qr-*` application repos

### Context Persistence

Long-term context and architecture decisions are stored in:
- `qr-docs` repository (public documentation)
- Issue templates with structured metadata
- PR descriptions with decision records

## Incident Response

### Security Alert Workflow

1. **Detection**: Dependabot/CodeQL/Secret scanning alerts
2. **Triage**: Security team reviews within 4 hours
3. **Response**: 
   - Critical: Immediate patch within 24 hours
   - High: Patch within 7 days
   - Medium: Patch within 30 days
   - Low: Next release cycle
4. **Disclosure**: Follow responsible disclosure guidelines

### Contact

- Security Team: `@QuantumRishi/security`
- Email: `security@quantum-rishi.com`

---

© 2024 SV Enterprises (Quantum Rishi)
