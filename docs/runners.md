# Self-Hosted Runners Guide

Guide for setting up and managing self-hosted GitHub Actions runners for QuantumRishi.

## Overview

Self-hosted runners provide:
- **Performance**: Faster builds with cached dependencies
- **Security**: Isolated environment for sensitive operations
- **Cost**: Reduced GitHub Actions minutes
- **Control**: Custom software and network access

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    QuantumRishi Runners                    │
├─────────────────────────────────────────────────────────┤
│  qr-runner-1  │  Linux ARM64  │  Build/Test            │
├─────────────────────────────────────────────────────────┤
│  qr-runner-2  │  Linux x64    │  Build/Test/Deploy     │
├─────────────────────────────────────────────────────────┤
│  qr-runner-3  │  Linux x64    │  Production Deploy     │
└─────────────────────────────────────────────────────────┘
```

## Runner Registration

### Prerequisites

1. **Bot Account**: `qr-bot` (machine user)
2. **PAT Scopes**: `repo`, `workflow`, `admin:org`
3. **SSH Access**: For internal network resources

### Installation Script

```bash
#!/bin/bash
# Install self-hosted runner for QuantumRishi

set -e

RUNNER_VERSION="2.319.1"
RUNNER_NAME="qr-runner-$(hostname)"
ORG="QuantumRishi"

# Download runner
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Get registration token
TOKEN=$(curl -s -X POST \
  -H "Authorization: token ${QR_BOT_PAT}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" \
  | jq -r '.token')

# Configure runner
./config.sh \
  --url "https://github.com/${ORG}" \
  --token "${TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "self-hosted,linux,x64,qr" \
  --work "_work" \
  --unattended

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

### Labels

| Label | Description |
|-------|-------------|
| `self-hosted` | All self-hosted runners |
| `linux` | Linux OS |
| `x64` / `arm64` | Architecture |
| `qr` | QuantumRishi runners |
| `deploy` | Authorized for deployments |
| `production` | Production environment access |

## Usage in Workflows

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, qr]
    steps:
      - uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332
      # ...

  deploy-prod:
    runs-on: [self-hosted, production]
    environment: production
    steps:
      # ...
```

## Security

### Runner Isolation

- Runners use ephemeral workspaces
- Secrets cleaned after each job
- Network segmentation for production runners

### Required Hardening

1. **Non-root execution**: Runners run as `github-runner` user
2. **Firewall rules**: Outbound only to GitHub and Cloudflare
3. **Automatic updates**: Runner auto-updates enabled
4. **Audit logging**: All actions logged to SIEM

## Troubleshooting

### Common Issues

1. **Runner offline**: Check `sudo ./svc.sh status`
2. **Token expired**: Re-register with new token
3. **Disk full**: Clear `_work` directory

### Logs

```bash
# Runner logs
journalctl -u actions.runner.QuantumRishi.qr-runner-1

# Worker logs
cat ~/actions-runner/_diag/Worker_*.log
```
