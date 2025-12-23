# qr-pipeline

Reusable CI/CD workflows and shared pipeline configurations for QuantumRishi ecosystem.

## Overview

This repository provides:
- **Reusable Workflows**: Standardized CI/CD patterns for all qr-* repositories
- **Composite Actions**: Shared steps for common operations
- **Security Hardening**: All actions pinned by SHA with step-security/harden-runner

## Workflows

| Workflow | Purpose | Trigger |
|----------|---------|--------|
| `lint.yml` | Code quality (ESLint, Prettier, TypeScript) | `workflow_call` |
| `unit.yml` | Unit tests with coverage | `workflow_call` |
| `e2e.yml` | End-to-end tests (Playwright) | `workflow_call` |
| `deploy-pages.yml` | Deploy to GitHub Pages | `workflow_call` |
| `deploy-workers.yml` | Deploy to Cloudflare Workers | `workflow_call` |
| `notify.yml` | Slack/Discord notifications | `workflow_call` |

## Usage

### In your repository

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint:
    uses: QuantumRishi/qr-pipeline/.github/workflows/lint.yml@main
    secrets: inherit

  test:
    uses: QuantumRishi/qr-pipeline/.github/workflows/unit.yml@main
    secrets: inherit
    with:
      coverage-threshold: 80
```

## Security

### SHA Pinning Policy

All external actions MUST be pinned by full SHA:

```yaml
# ✅ Good - SHA pinned
uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7

# ❌ Bad - tag reference
uses: actions/checkout@v4
```

### Harden Runner

All workflows include step-security/harden-runner:

```yaml
- name: Harden Runner
  uses: step-security/harden-runner@17d0e2bd7d51742c71671bd19fa12bdc9d40a3d6 # v2.8.1
  with:
    egress-policy: audit
```

## Required Secrets

| Secret | Scope | Purpose |
|--------|-------|--------|
| `QR_BOT_PAT` | org | Cross-repo operations |
| `CLOUDFLARE_API_TOKEN` | repo | Workers deployments |
| `CLOUDFLARE_ACCOUNT_ID` | repo | Workers account |
| `SLACK_WEBHOOK_URL` | org | Notifications |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT © QuantumRishi
