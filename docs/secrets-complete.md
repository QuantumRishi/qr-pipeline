# Complete Secrets Schema for QuantumRishi Infrastructure

Comprehensive secrets management for all environments.

## Table of Contents

1. [Organization Secrets](#organization-secrets)
2. [Repository Secrets](#repository-secrets)
3. [Vault Secret Paths](#vault-secret-paths)
4. [Secret Creation Commands](#secret-creation-commands)
5. [Rotation Schedule](#rotation-schedule)
6. [Workflow Usage](#workflow-usage)

---

## Organization Secrets

Secrets shared across all QuantumRishi repositories:

| Secret Name | Description | Required By | Rotation |
|-------------|-------------|-------------|----------|
| `QR_BOT_PAT` | GitHub PAT (fine-grained) for qr-bot | All workflows | 90 days |
| `CLOUDFLARE_API_TOKEN` | CF API token (Zone:Edit, Workers:Edit) | deploy-* | 180 days |
| `CLOUDFLARE_ACCOUNT_ID` | CF account identifier | deploy-* | Static |
| `SLACK_WEBHOOK_URL` | Slack notifications | notify.yml | As needed |
| `DISCORD_WEBHOOK_URL` | Discord notifications | notify.yml | As needed |
| `CODECOV_TOKEN` | Code coverage upload | ci-base.yml | Static |

### Fine-Grained PAT Permissions (QR_BOT_PAT)

```yaml
Repository permissions:
  - Actions: Read and write
  - Contents: Read and write
  - Issues: Read and write
  - Pull requests: Read and write
  - Workflows: Read and write

Organization permissions:
  - Members: Read
  - Self-hosted runners: Read and write
```

---

## Repository Secrets

### qr.dev (Frontend/App)

| Secret | Description | Source |
|--------|-------------|--------|
| `SUPABASE_URL` | `https://db.quantum-rishi.com` | Vault |
| `SUPABASE_ANON_KEY` | Supabase anonymous (public) key | Vault |
| `SUPABASE_SERVICE_KEY` | Supabase service role key | Vault |
| `VITE_APP_VERSION` | App version (set by CI) | CI |

### qr-db (Database)

| Secret | Description | Source |
|--------|-------------|--------|
| `POSTGRES_PASSWORD` | PostgreSQL superuser password | Vault |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role JWT | Vault |
| `JWT_SECRET` | JWT signing secret (32+ chars) | Vault |
| `ANON_KEY` | Anonymous role JWT | Vault |

### qr-mail (Email)

| Secret | Description | Source |
|--------|-------------|--------|
| `SMTP_USER` | SMTP authentication username | Vault |
| `SMTP_PASSWORD` | SMTP authentication password | Vault |
| `DKIM_PRIVATE_KEY` | DKIM signing key (base64) | Vault |
| `RESEND_API_KEY` | Resend transactional email API | Vault |

### qr-pipeline (CI/CD)

| Secret | Description | Source |
|--------|-------------|--------|
| `RUNNER_TOKEN` | Self-hosted runner registration | GitHub API |
| `VAULT_TOKEN` | HashiCorp Vault access token | Vault |
| `VAULT_ADDR` | Vault server address | Config |

---

## Vault Secret Paths

All production secrets stored in HashiCorp Vault:

```
secret/data/qr/
├── common/
│   ├── jwt                    # JWT_SECRET, JWT_EXPIRY
│   └── encryption             # AES keys for data encryption
├── dev/
│   ├── supabase              # SUPABASE_URL, *_KEY
│   ├── cloudflare            # API tokens
│   └── smtp                  # Dev SMTP credentials
├── staging/
│   ├── supabase
│   ├── cloudflare
│   └── smtp
└── prod/
    ├── supabase              # Production Supabase keys
    ├── cloudflare            # Production CF tokens
    ├── smtp                  # Production SMTP
    ├── db                    # PostgreSQL credentials
    ├── minio                 # Object storage keys
    └── dkim                  # DKIM private key

transit/keys/
└── qr-encrypt                # Encryption key for sensitive data

pki/
└── qr-internal               # Internal TLS certificates
```

---

## Secret Creation Commands

### GitHub Organization Secrets

```bash
#!/bin/bash
# Create organization secrets using GitHub CLI

# Set org name
ORG="QuantumRishi"

# PAT for bot account (generate from GitHub settings)
gh secret set QR_BOT_PAT --org $ORG

# Cloudflare credentials
gh secret set CLOUDFLARE_API_TOKEN --org $ORG
gh secret set CLOUDFLARE_ACCOUNT_ID --org $ORG --body "YOUR_ACCOUNT_ID"

# Notifications
gh secret set SLACK_WEBHOOK_URL --org $ORG
gh secret set DISCORD_WEBHOOK_URL --org $ORG

# Code coverage
gh secret set CODECOV_TOKEN --org $ORG
```

### Repository Secrets

```bash
#!/bin/bash
# Create repository-specific secrets

# qr.dev secrets
gh secret set SUPABASE_URL --repo QuantumRishi/qr.dev
gh secret set SUPABASE_ANON_KEY --repo QuantumRishi/qr.dev
gh secret set SUPABASE_SERVICE_KEY --repo QuantumRishi/qr.dev

# qr-db secrets
gh secret set POSTGRES_PASSWORD --repo QuantumRishi/qr-db
gh secret set JWT_SECRET --repo QuantumRishi/qr-db

# qr-mail secrets
gh secret set DKIM_PRIVATE_KEY --repo QuantumRishi/qr-mail
gh secret set SMTP_PASSWORD --repo QuantumRishi/qr-mail
```

### Vault Secret Creation

```bash
#!/bin/bash
# Store secrets in HashiCorp Vault

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Common secrets
vault kv put secret/qr/common/jwt \
  JWT_SECRET="$(openssl rand -base64 32)" \
  JWT_EXPIRY="7d"

# Production Supabase
vault kv put secret/qr/prod/supabase \
  SUPABASE_URL="https://db.quantum-rishi.com" \
  SUPABASE_ANON_KEY="eyJ..." \
  SUPABASE_SERVICE_KEY="eyJ..."

# Production SMTP
vault kv put secret/qr/prod/smtp \
  SMTP_HOST="mail.quantum-rishi.com" \
  SMTP_PORT="587" \
  SMTP_USER="hello@quantum-rishi.com" \
  SMTP_PASSWORD="$(openssl rand -base64 24)"

# Production MinIO
vault kv put secret/qr/prod/minio \
  MINIO_ACCESS_KEY="$(openssl rand -hex 16)" \
  MINIO_SECRET_KEY="$(openssl rand -base64 32)"

# DKIM key
vault kv put secret/qr/prod/dkim \
  DKIM_PRIVATE_KEY="$(base64 -w0 < /etc/opendkim/keys/quantum-rishi.com/qr2024.private)"
```

### Generate JWT Secret

```bash
# Generate a secure 256-bit JWT secret
openssl rand -base64 32

# Or using Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

---

## Rotation Schedule

| Secret | Rotation Period | Method |
|--------|-----------------|--------|
| `QR_BOT_PAT` | 90 days | Manual (GitHub Settings) |
| `JWT_SECRET` | 180 days | Vault + App restart |
| `SMTP_PASSWORD` | 90 days | Vault + Dovecot reload |
| `DKIM_PRIVATE_KEY` | Yearly | Generate new selector |
| `CLOUDFLARE_API_TOKEN` | 180 days | CF Dashboard |
| `POSTGRES_PASSWORD` | 90 days | Vault + DB restart |
| `MINIO_*` | 180 days | Vault + MinIO restart |

### Rotation Reminder Script

```bash
#!/bin/bash
# /etc/cron.weekly/check-secret-rotation

VAULT_ADDR="https://vault.quantum-rishi.com"
SLACK_WEBHOOK="$SLACK_WEBHOOK_URL"

# Check secret metadata for last update
check_secret() {
  local path=$1
  local max_age_days=$2
  
  metadata=$(vault kv metadata get -format=json "$path" 2>/dev/null)
  if [ $? -eq 0 ]; then
    updated=$(echo "$metadata" | jq -r '.data.updated_time')
    updated_epoch=$(date -d "$updated" +%s)
    now_epoch=$(date +%s)
    age_days=$(( (now_epoch - updated_epoch) / 86400 ))
    
    if [ $age_days -gt $max_age_days ]; then
      echo "WARNING: $path is $age_days days old (max: $max_age_days)"
      return 1
    fi
  fi
  return 0
}

# Check critical secrets
warnings=""
check_secret "secret/qr/prod/jwt" 180 || warnings+="JWT_SECRET needs rotation\n"
check_secret "secret/qr/prod/smtp" 90 || warnings+="SMTP credentials need rotation\n"
check_secret "secret/qr/prod/db" 90 || warnings+="DB credentials need rotation\n"

# Send Slack notification if warnings exist
if [ -n "$warnings" ]; then
  curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\":warning: Secret Rotation Required\n$warnings\"}" \
    "$SLACK_WEBHOOK"
fi
```

---

## Workflow Usage

### Accessing Org Secrets

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to Cloudflare
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
        run: |
          wrangler deploy
```

### Accessing Vault Secrets

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, qr]
    steps:
      - name: Import Vault Secrets
        uses: hashicorp/vault-action@v3
        with:
          url: https://vault.quantum-rishi.com
          method: jwt
          role: qr-deploy
          secrets: |
            secret/data/qr/prod/supabase SUPABASE_SERVICE_KEY | SUPABASE_SERVICE_KEY ;
            secret/data/qr/prod/smtp SMTP_PASSWORD | SMTP_PASSWORD
      
      - name: Deploy
        env:
          SUPABASE_SERVICE_KEY: ${{ env.SUPABASE_SERVICE_KEY }}
        run: |
          # Deploy commands...
```

### Environment-Specific Secrets

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production  # Uses production environment secrets
    steps:
      - name: Deploy
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
        run: |
          # Deploy commands...
```

---

## Security Best Practices

1. **Never commit secrets** to Git repositories
2. **Use fine-grained PATs** instead of classic tokens
3. **Rotate secrets regularly** per the schedule above
4. **Use Vault** for production secrets when possible
5. **Audit secret access** via GitHub audit log
6. **Use environment protection** rules for production
7. **Limit secret scope** to minimum required repositories
