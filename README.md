# QR Pipeline

> Shared CI/CD workflows for the Quantum Rishi ecosystem

[![Security Hardened](https://img.shields.io/badge/security-hardened-green)](https://github.com/step-security/harden-runner)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This repository contains reusable GitHub Actions workflows for all QuantumRishi organization repositories. All workflows follow security best practices including:

- 🔐 **Pinned Actions by SHA** - All actions are pinned to specific commit SHAs
- 🛡️ **Hardened Runners** - Using step-security/harden-runner for all jobs
- 🔒 **Minimal Permissions** - Least-privilege principle for all workflows
- 📊 **Security Scanning** - CodeQL, dependency review, and secrets scanning

## Available Workflows

### CI Base (`workflows/ci-base.yml`)

Base CI workflow with linting, type checking, and testing.

```yaml
jobs:
  ci:
    uses: QuantumRishi/qr-pipeline/.github/workflows/ci-base.yml@main
    with:
      node-version: '20'
      pnpm-version: '9'
      run-tests: true
      run-lint: true
      run-typecheck: true
```

### Deploy to Vercel (`workflows/deploy-vercel.yml`)

Deploy to Vercel with preview/production environments.

```yaml
jobs:
  deploy:
    uses: QuantumRishi/qr-pipeline/.github/workflows/deploy-vercel.yml@main
    with:
      environment: production
    secrets:
      VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
      VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
      VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
```

### Deploy to Cloudflare (`workflows/deploy-cloudflare.yml`)

Deploy to Cloudflare Workers or Pages.

```yaml
jobs:
  deploy:
    uses: QuantumRishi/qr-pipeline/.github/workflows/deploy-cloudflare.yml@main
    with:
      type: pages
      project-name: qr-app
      directory: dist
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### Security Scan (`workflows/security-scan.yml`)

Comprehensive security scanning including CodeQL, dependency review, and secrets detection.

```yaml
jobs:
  security:
    uses: QuantumRishi/qr-pipeline/.github/workflows/security-scan.yml@main
    with:
      run-codeql: true
      run-dependency-review: true
      run-secrets-scan: true
      languages: 'javascript,typescript'
```

### Supabase Migration (`workflows/supabase-migrate.yml`)

Run Supabase database migrations.

```yaml
jobs:
  migrate:
    uses: QuantumRishi/qr-pipeline/.github/workflows/supabase-migrate.yml@main
    with:
      environment: production
    secrets:
      SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
      SUPABASE_PROJECT_ID: ${{ secrets.SUPABASE_PROJECT_ID }}
      SUPABASE_DB_PASSWORD: ${{ secrets.SUPABASE_DB_PASSWORD }}
```

## Security Configuration

### Organization-Level Secrets

Set these secrets at the organization level (`QuantumRishi`):

| Secret | Description |
|--------|-------------|
| `VERCEL_TOKEN` | Vercel deployment token |
| `VERCEL_ORG_ID` | Vercel organization ID |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |
| `SUPABASE_ACCESS_TOKEN` | Supabase management API token |
| `NPM_TOKEN` | NPM publish token (if needed) |

### Recommended Actions Settings

1. **Restrict PR approval**: Disable "Allow GitHub Actions to create and approve pull requests"
2. **Workflow permissions**: Set to "Read repository contents and packages permissions"
3. **Fork PR policies**: Require approval for first-time contributors
4. **Action allowlist**: Only allow actions from verified creators

## Usage Example

Create `.github/workflows/ci.yml` in your repository:

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: QuantumRishi/qr-pipeline/.github/workflows/ci-base.yml@main
    with:
      node-version: '20'

  security:
    uses: QuantumRishi/qr-pipeline/.github/workflows/security-scan.yml@main
    permissions:
      security-events: write
      contents: read

  deploy:
    needs: [ci, security]
    if: github.ref == 'refs/heads/main'
    uses: QuantumRishi/qr-pipeline/.github/workflows/deploy-vercel.yml@main
    with:
      environment: production
    secrets: inherit
```

## License

MIT © [SV Enterprises](https://quantum-rishi.com)
