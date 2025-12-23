# Production Deployment Runbook for QuantumRishi

Step-by-step guide for setting up production infrastructure.

## Table of Contents

1. [Pre-requisites](#pre-requisites)
2. [DNS Configuration](#dns-configuration)
3. [Cloudflare Setup](#cloudflare-setup)
4. [Mail Server Setup](#mail-server-setup)
5. [SSL Certificates](#ssl-certificates)
6. [Self-Hosted Runners](#self-hosted-runners)
7. [Secrets Configuration](#secrets-configuration)
8. [Verification Checklist](#verification-checklist)

---

## Pre-requisites

### Required Access

- [ ] Cloudflare account with `quantum-rishi.com` zone
- [ ] Server with SSH access (for db, mail services)
- [ ] GitHub organization admin access to QuantumRishi
- [ ] HashiCorp Vault instance (optional, for production secrets)

### Required Tools

```bash
# Install required CLI tools
brew install gh cloudflare/cloudflare/cloudflared terraform vault

# Or on Ubuntu/Debian
apt-get install -y curl jq
curl -s https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list
apt-get update && apt-get install gh
```

---

## DNS Configuration

### Step 1: Configure Cloudflare Zone

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to `quantum-rishi.com` zone
3. Ensure nameservers are set at your registrar

### Step 2: Apply Terraform Configuration

```bash
cd infrastructure/cloudflare

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add your values

# Initialize and apply
terraform init
terraform plan
terraform apply
```

### Step 3: Manual DNS Records (if not using Terraform)

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | @ | YOUR_SERVER_IP | Off | 300 |
| A | db | YOUR_SERVER_IP | Off | 300 |
| A | mail | YOUR_MAIL_IP | Off | 300 |
| CNAME | app | qr-dev.pages.dev | On | Auto |
| CNAME | api | qr-api.workers.dev | On | Auto |
| MX | @ | mail.quantum-rishi.com | - | 300 |
| TXT | @ | v=spf1 mx ip4:YOUR_IP -all | - | 300 |
| TXT | _dmarc | v=DMARC1; p=reject; ... | - | 300 |
| TXT | qr2024._domainkey | v=DKIM1; k=rsa; p=... | - | 300 |
| TXT | _mta-sts | v=STSv1; id=20241223001 | - | 300 |
| TXT | _smtp._tls | v=TLSRPTv1; rua=mailto:... | - | 300 |

### Step 4: Verify DNS Propagation

```bash
# Check all records
dig A quantum-rishi.com +short
dig A app.quantum-rishi.com +short
dig A api.quantum-rishi.com +short
dig A db.quantum-rishi.com +short
dig A mail.quantum-rishi.com +short
dig MX quantum-rishi.com +short
dig TXT quantum-rishi.com +short
dig TXT _dmarc.quantum-rishi.com +short
```

---

## Cloudflare Setup

### Step 1: Configure SSL/TLS

In Cloudflare Dashboard:

1. SSL/TLS → Overview → Select "Full (strict)"
2. SSL/TLS → Edge Certificates → Enable:
   - Always Use HTTPS
   - Automatic HTTPS Rewrites
   - TLS 1.3
   - Minimum TLS Version: 1.2

### Step 2: Configure Security

1. Security → Settings:
   - Security Level: High
   - Challenge Passage: 30 minutes
   - Browser Integrity Check: On

2. Security → Bots:
   - Bot Fight Mode: On

### Step 3: Configure Pages Project

```bash
# Create Pages project
wrangler pages project create qr-dev

# Connect to repository
# Dashboard → Pages → qr-dev → Settings → Builds & deployments
# - Production branch: main
# - Build command: pnpm build
# - Build output directory: build/client
```

### Step 4: Configure Workers

```bash
# Deploy API worker
cd /path/to/qr.dev
wrangler deploy --env production
```

---

## Mail Server Setup

### Step 1: Install Packages

```bash
apt-get update
apt-get install -y postfix dovecot-imapd dovecot-lmtpd opendkim opendkim-tools rspamd
```

### Step 2: Configure Postfix

```bash
# Copy configuration
cp infrastructure/mail/postfix/main.cf /etc/postfix/main.cf
cp infrastructure/mail/postfix/master.cf /etc/postfix/master.cf

# Edit with your values
vim /etc/postfix/main.cf

# Create virtual mailbox database
postmap /etc/postfix/vmailbox
postmap /etc/postfix/virtual
```

### Step 3: Configure Dovecot

```bash
cp infrastructure/mail/dovecot/dovecot.conf /etc/dovecot/dovecot.conf

# Create vmail user
groupadd -g 5000 vmail
useradd -u 5000 -g vmail -s /usr/sbin/nologin -d /var/mail/vhosts vmail
mkdir -p /var/mail/vhosts/quantum-rishi.com
chown -R vmail:vmail /var/mail/vhosts
```

### Step 4: Generate DKIM Keys

```bash
mkdir -p /etc/opendkim/keys/quantum-rishi.com
cd /etc/opendkim/keys/quantum-rishi.com

# Generate key
opendkim-genkey -s qr2024 -d quantum-rishi.com -b 2048

# Set permissions
chown opendkim:opendkim qr2024.private
chmod 600 qr2024.private

# Get public key for DNS
cat qr2024.txt
# Copy the p=... value to Cloudflare DNS
```

### Step 5: Start Services

```bash
systemctl enable --now postfix dovecot opendkim rspamd
```

---

## SSL Certificates

### Step 1: Install Certbot

```bash
apt-get install -y certbot python3-certbot-dns-cloudflare
```

### Step 2: Create Cloudflare Credentials

```bash
# Create credentials file
cat > /root/.cloudflare-credentials << EOF
dns_cloudflare_api_token = YOUR_API_TOKEN
EOF
chmod 600 /root/.cloudflare-credentials
```

### Step 3: Obtain Certificate

```bash
# Run the setup script
chmod +x scripts/setup-ssl-cert.sh
./scripts/setup-ssl-cert.sh
```

### Step 4: Configure Auto-Renewal

```bash
# Install systemd timer
cp infrastructure/systemd/certbot-renewal.timer /etc/systemd/system/
cp infrastructure/systemd/certbot-renewal.service /etc/systemd/system/

# Install renewal hook
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cp scripts/ssl-renewal-hook.sh /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh

# Enable timer
systemctl daemon-reload
systemctl enable --now certbot-renewal.timer
```

### Step 5: Verify Certificates

```bash
chmod +x scripts/verify-tls.sh
./scripts/verify-tls.sh
```

---

## Self-Hosted Runners

### Step 1: Prepare Server

```bash
# System requirements
apt-get update
apt-get install -y curl jq git

# Create firewall rules (optional)
ufw allow from 140.82.112.0/20 to any port 443  # GitHub
ufw enable
```

### Step 2: Generate PAT

1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (fine-grained)
3. Select QuantumRishi organization
4. Permissions:
   - Actions: Read and write
   - Administration: Read and write
   - Contents: Read

### Step 3: Install Runner

```bash
export QR_BOT_PAT="ghp_..."  # Your PAT

chmod +x scripts/install-runner.sh
./scripts/install-runner.sh
```

### Step 4: Add Labels

```bash
# In GitHub → Settings → Actions → Runners
# Add labels: qr, secure, no-docker (as needed)
```

### Step 5: Verify Runner

```bash
qr-runner status
```

---

## Secrets Configuration

### Step 1: Create Organization Secrets

```bash
gh auth login

# Organization secrets
gh secret set QR_BOT_PAT --org QuantumRishi
gh secret set CLOUDFLARE_API_TOKEN --org QuantumRishi
gh secret set CLOUDFLARE_ACCOUNT_ID --org QuantumRishi --body "YOUR_ACCOUNT_ID"
gh secret set SLACK_WEBHOOK_URL --org QuantumRishi
```

### Step 2: Create Repository Secrets

```bash
# qr.dev
gh secret set SUPABASE_URL --repo QuantumRishi/qr.dev
gh secret set SUPABASE_ANON_KEY --repo QuantumRishi/qr.dev
gh secret set SUPABASE_SERVICE_KEY --repo QuantumRishi/qr.dev

# qr-db
gh secret set POSTGRES_PASSWORD --repo QuantumRishi/qr-db
gh secret set JWT_SECRET --repo QuantumRishi/qr-db

# qr-mail
gh secret set DKIM_PRIVATE_KEY --repo QuantumRishi/qr-mail
gh secret set SMTP_PASSWORD --repo QuantumRishi/qr-mail
```

### Step 3: Configure Vault (Optional)

```bash
export VAULT_ADDR="https://vault.quantum-rishi.com"
vault login

# Add policies
vault policy write qr-deploy infrastructure/vault/policies/qr-deploy.hcl
vault policy write qr-admin infrastructure/vault/policies/qr-admin.hcl

# Add secrets
vault kv put secret/qr/prod/supabase \
  url="https://db.quantum-rishi.com" \
  anon_key="eyJ..." \
  service_key="eyJ..."
```

---

## Verification Checklist

### DNS & Cloudflare

- [ ] A records resolve correctly
- [ ] CNAME records proxy through Cloudflare
- [ ] MX record points to mail server
- [ ] SPF record configured
- [ ] DKIM record configured
- [ ] DMARC record configured
- [ ] MTA-STS record configured
- [ ] SSL/TLS set to Full (strict)

### Mail Server

- [ ] Postfix accepting mail on port 25
- [ ] Submission working on port 587
- [ ] SMTPS working on port 465
- [ ] IMAPS working on port 993
- [ ] DKIM signing working
- [ ] SPF checking working
- [ ] Send test email via mail-tester.com

### SSL Certificates

- [ ] Certificate valid for mail.quantum-rishi.com
- [ ] Auto-renewal timer enabled
- [ ] verify-tls.sh passes all checks

### Self-Hosted Runners

- [ ] Runner appears in GitHub → Settings → Actions → Runners
- [ ] Runner has correct labels (qr, secure, no-docker)
- [ ] Test workflow runs on self-hosted runner

### Secrets

- [ ] Organization secrets created
- [ ] Repository secrets created
- [ ] Vault policies applied (if using Vault)
- [ ] Workflow can access secrets

### Final Verification

```bash
# Run all verification scripts
./scripts/verify-tls.sh
./scripts/verify-pins.sh

# Test CI pipeline
gh workflow run ci.yml --repo QuantumRishi/qr.dev

# Test deployment
gh workflow run deploy.yml --repo QuantumRishi/qr.dev -f environment=staging
```

---

## Troubleshooting

### DNS Issues

```bash
# Check propagation
dig +trace app.quantum-rishi.com

# Flush DNS cache
sudo systemd-resolve --flush-caches  # Linux
dscacheutil -flushcache  # macOS
```

### Mail Issues

```bash
# Check mail logs
journalctl -u postfix -f
journalctl -u dovecot -f

# Test SMTP
openssl s_client -connect mail.quantum-rishi.com:587 -starttls smtp

# Test IMAP
openssl s_client -connect mail.quantum-rishi.com:993
```

### Runner Issues

```bash
# Check runner status
qr-runner status
qr-runner logs

# Restart runner
qr-runner restart
```

### SSL Issues

```bash
# Check certificate
openssl x509 -in /etc/letsencrypt/live/mail.quantum-rishi.com/fullchain.pem -noout -dates

# Force renewal
certbot renew --force-renewal
```
