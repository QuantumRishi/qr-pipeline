# GitHub Secrets & Self-Hosted Runners Setup

Complete guide for configuring GitHub secrets and self-hosted runners.

## Organization Secrets

### Adding Org-Level Secrets

1. Go to **github.com/QuantumRishi** → Settings → Secrets and variables → Actions
2. Click "New organization secret"
3. Add each secret with appropriate repository access

### Required Organization Secrets

| Secret | Description | Repositories |
|--------|-------------|-------------|
| `QR_BOT_PAT` | GitHub PAT for qr-bot machine user | All |
| `SLACK_WEBHOOK_URL` | Slack notifications | All |
| `DISCORD_WEBHOOK_URL` | Discord notifications | All |
| `NPM_TOKEN` | NPM publish token | Selected |
| `CODECOV_TOKEN` | Code coverage upload | All |

### Creating the Bot PAT

1. Sign in as `qr-bot` machine user
2. Settings → Developer settings → Personal access tokens → Fine-grained tokens
3. Generate new token:
   - **Name:** `qr-bot-actions`
   - **Expiration:** 90 days
   - **Repository access:** All repositories (or selected)
   - **Permissions:**
     ```
     Repository:
       Contents: Read and write
       Metadata: Read-only
       Pull requests: Read and write
       Workflows: Read and write
     Organization:
       Members: Read-only
     ```
4. Copy token and add as `QR_BOT_PAT` org secret

## Repository Secrets

### qr.dev Secrets

```bash
# Using GitHub CLI
gh secret set SUPABASE_URL --repo QuantumRishi/qr.dev
gh secret set SUPABASE_ANON_KEY --repo QuantumRishi/qr.dev
gh secret set SUPABASE_SERVICE_KEY --repo QuantumRishi/qr.dev
gh secret set CLOUDFLARE_API_TOKEN --repo QuantumRishi/qr.dev
gh secret set CLOUDFLARE_ACCOUNT_ID --repo QuantumRishi/qr.dev
```

### qr-mail Secrets

```bash
gh secret set RESEND_API_KEY --repo QuantumRishi/qr-mail
gh secret set SMTP_PASSWORD --repo QuantumRishi/qr-mail
```

### qr-db Secrets

```bash
gh secret set POSTGRES_PASSWORD --repo QuantumRishi/qr-db
gh secret set VAULT_TOKEN --repo QuantumRishi/qr-db
gh secret set ENCRYPTION_KEY --repo QuantumRishi/qr-db
```

## Environment Secrets

### Creating Environments

1. Repository → Settings → Environments
2. Create environments: `development`, `staging`, `production`

### Production Environment Protection

```yaml
Environment: production
Protection rules:
  - Required reviewers: @QuantumRishi/devops
  - Wait timer: 15 minutes
  - Deployment branches: main only
```

### Environment-Specific Secrets

```
# Development
gh secret set SUPABASE_URL --env development --repo QuantumRishi/qr.dev

# Staging  
gh secret set SUPABASE_URL --env staging --repo QuantumRishi/qr.dev

# Production
gh secret set SUPABASE_URL --env production --repo QuantumRishi/qr.dev
```

## Self-Hosted Runners

### Server Preparation

```bash
# Create runner user
sudo useradd -m -s /bin/bash github-runner
sudo usermod -aG docker github-runner  # Only if Docker needed

# Install dependencies
sudo apt-get update
sudo apt-get install -y curl jq git build-essential

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install pnpm
npm install -g pnpm
```

### Runner Installation

```bash
# As github-runner user
su - github-runner

# Download runner
mkdir actions-runner && cd actions-runner
curl -o actions-runner-linux-x64-2.319.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-linux-x64-2.319.1.tar.gz
tar xzf actions-runner-linux-x64-2.319.1.tar.gz

# Get registration token
# Go to: github.com/QuantumRishi → Settings → Actions → Runners → New self-hosted runner
# Copy the token

# Configure
./config.sh \
  --url https://github.com/QuantumRishi \
  --token YOUR_TOKEN_HERE \
  --name qr-runner-1 \
  --labels self-hosted,linux,x64,qr,secure \
  --work _work \
  --unattended
```

### Runner Labels

| Label | Description | Use Case |
|-------|-------------|----------|
| `self-hosted` | Required by GitHub | All self-hosted jobs |
| `linux` | OS type | OS-specific jobs |
| `x64` / `arm64` | Architecture | Arch-specific builds |
| `qr` | QuantumRishi runner | Org-specific jobs |
| `secure` | Security-hardened | Sensitive deployments |
| `no-docker` | Docker not available | Jobs that shouldn't use Docker |
| `deploy` | Deployment authorized | Production deployments |

### Systemd Service

```bash
# Install as service
sudo ./svc.sh install github-runner
sudo ./svc.sh start
sudo ./svc.sh status

# Enable auto-start
sudo systemctl enable actions.runner.QuantumRishi.qr-runner-1
```

### Service File (Manual)

```ini
# /etc/systemd/system/github-runner.service
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=github-runner
WorkingDirectory=/home/github-runner/actions-runner
ExecStart=/home/github-runner/actions-runner/run.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Security Hardening

```bash
# Restrict runner user
sudo chmod 700 /home/github-runner
sudo chown -R github-runner:github-runner /home/github-runner

# Firewall (only outbound to GitHub)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# Disable password auth (SSH keys only)
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Auto-cleanup workspace
cat >> /home/github-runner/.bashrc << 'EOF'
# Cleanup old workspaces (older than 7 days)
find /home/github-runner/actions-runner/_work -maxdepth 2 -type d -mtime +7 -exec rm -rf {} \;
EOF
```

### Using Self-Hosted Runners in Workflows

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, qr]
    steps:
      - uses: actions/checkout@v4
      # ...

  deploy-production:
    runs-on: [self-hosted, secure, deploy]
    environment: production
    steps:
      # ...
```

## Runner Groups

### Creating Runner Groups

1. Organization → Settings → Actions → Runner groups
2. Create groups:
   - **Default**: All runners
   - **Production**: Only `secure` + `deploy` runners
   - **Development**: All other runners

### Group Policies

```yaml
# Production group
Workflow access: Selected workflows
Allowed workflows:
  - QuantumRishi/qr.dev/.github/workflows/deploy-production.yml
  - QuantumRishi/qr-pipeline/.github/workflows/deploy-workers.yml
```

## Monitoring

### Runner Status Check

```bash
#!/bin/bash
# /opt/scripts/check-runner.sh

RUNNER_DIR=/home/github-runner/actions-runner
STATUS=$(sudo systemctl is-active actions.runner.QuantumRishi.qr-runner-1)

if [ "$STATUS" != "active" ]; then
  echo "Runner is down, restarting..."
  sudo systemctl restart actions.runner.QuantumRishi.qr-runner-1
  # Send alert to Slack
  curl -X POST "$SLACK_WEBHOOK" -d '{"text": "⚠️ Runner qr-runner-1 was restarted"}'
fi
```

### Cron Job for Monitoring

```bash
# /etc/cron.d/github-runner-monitor
*/5 * * * * root /opt/scripts/check-runner.sh >> /var/log/runner-monitor.log 2>&1
```

## Secret Rotation

### Rotation Schedule

| Secret Type | Rotation Period | Notification |
|-------------|-----------------|-------------|
| PATs | 90 days | 14 days before |
| API Keys | 180 days | 30 days before |
| Passwords | 90 days | 14 days before |
| JWT Secrets | 30 days | 7 days before |

### Rotation Script

```bash
#!/bin/bash
# /opt/scripts/rotate-secrets.sh

# Rotate JWT secret
NEW_SECRET=$(openssl rand -base64 32)
gh secret set JWT_SECRET --body "$NEW_SECRET" --repo QuantumRishi/qr.dev

# Update Vault
vault kv put secret/qr/prod/jwt signing_key="$NEW_SECRET"

echo "JWT secret rotated at $(date)"
```

## Troubleshooting

### Runner Not Picking Up Jobs

```bash
# Check runner status
sudo systemctl status actions.runner.QuantumRishi.qr-runner-1

# View runner logs
journalctl -u actions.runner.QuantumRishi.qr-runner-1 -f

# Check connectivity
curl -I https://github.com
curl -I https://api.github.com
```

### Re-registering Runner

```bash
# Remove old registration
cd /home/github-runner/actions-runner
./config.sh remove --token YOUR_REMOVE_TOKEN

# Re-register
./config.sh --url https://github.com/QuantumRishi --token NEW_TOKEN ...
```

### Secret Not Available

1. Check secret scope (org vs repo)
2. Verify environment protection rules
3. Check repository access for org secrets
4. Verify workflow has correct `secrets: inherit`
