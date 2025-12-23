# DNS & Cloudflare Setup Guide

Comprehensive DNS configuration for QuantumRishi infrastructure.

## Domain Structure

```
quantum-rishi.com (apex)
├── app.quantum-rishi.com    → Cloudflare Pages (qr.dev frontend)
├── api.quantum-rishi.com    → Cloudflare Workers (middleware/edge)
├── db.quantum-rishi.com     → Self-hosted Supabase (PostgreSQL)
├── mail.quantum-rishi.com   → qr-mail MTA (Postfix/Dovecot)
└── docs.quantum-rishi.com   → GitHub Pages (documentation)
```

## Cloudflare Configuration

### 1. Add Domain to Cloudflare

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Add Site → `quantum-rishi.com`
3. Select Free or Pro plan
4. Update nameservers at your registrar:
   ```
   ns1.cloudflare.com
   ns2.cloudflare.com
   ```

### 2. DNS Records

```
# A Records (replace with your server IPs)
@               A       YOUR_SERVER_IP          (proxied off)
db              A       YOUR_DB_SERVER_IP       (proxied off)
mail            A       YOUR_MAIL_SERVER_IP     (proxied off)

# CNAME Records (Cloudflare services)
app             CNAME   qr-dev.pages.dev        (proxied on)
api             CNAME   qr-api.workers.dev      (proxied on)
docs            CNAME   quantumrishi.github.io  (proxied on)

# MX Records
@               MX      10 mail.quantum-rishi.com

# TXT Records (Email security)
@               TXT     "v=spf1 mx ip4:YOUR_MAIL_IP include:_spf.google.com ~all"
_dmarc          TXT     "v=DMARC1; p=quarantine; rua=mailto:dmarc@quantum-rishi.com"
qr2024._domainkey TXT   "v=DKIM1; k=rsa; p=<YOUR_DKIM_PUBLIC_KEY>"

# CAA Records (Certificate Authority Authorization)
@               CAA     0 issue "letsencrypt.org"
@               CAA     0 issue "digicert.com"
@               CAA     0 issuewild "letsencrypt.org"
```

### 3. SSL/TLS Settings

**Cloudflare Dashboard → SSL/TLS:**

| Setting | Value |
|---------|-------|
| SSL/TLS encryption mode | Full (strict) |
| Always Use HTTPS | On |
| Minimum TLS Version | TLS 1.2 |
| Automatic HTTPS Rewrites | On |
| TLS 1.3 | On |
| HSTS | Enable (max-age 31536000, includeSubDomains) |

### 4. Security Settings

**Cloudflare Dashboard → Security:**

| Setting | Value |
|---------|-------|
| Security Level | High |
| Challenge Passage | 30 minutes |
| Browser Integrity Check | On |
| Email Address Obfuscation | On |
| Server-side Excludes | On |
| Hotlink Protection | On |

## Cloudflare Pages (Frontend)

### Deploy qr.dev to Pages

```bash
# In qr.dev repository
cd apps/app

# Connect to Cloudflare Pages
# Dashboard → Pages → Create Project → Connect to Git

# Build settings:
#   Framework preset: None (custom)
#   Build command: pnpm build
#   Build output directory: build/client
#   Root directory: apps/app
```

### Environment Variables (Pages)

```
NODE_VERSION=20
SUPABASE_URL=https://db.quantum-rishi.com
SUPABASE_ANON_KEY=<from-vault>
```

### Custom Domain

1. Pages → qr-dev → Custom domains
2. Add `app.quantum-rishi.com`
3. Cloudflare auto-provisions SSL

## Cloudflare Workers (API/Middleware)

### Deploy Worker

```bash
# In qr.dev repository
cd packages/worker-middleware

# Deploy to production
pnpm wrangler deploy --env production
```

### wrangler.toml Configuration

```toml
name = "qr-api"
main = "src/index.ts"
compatibility_date = "2024-10-01"

[env.production]
route = { pattern = "api.quantum-rishi.com/*", zone_name = "quantum-rishi.com" }

[vars]
ENVIRONMENT = "production"
```

### Worker Secrets

```bash
# Set secrets via wrangler
wrangler secret put JWT_SECRET --env production
wrangler secret put SUPABASE_SERVICE_KEY --env production
```

## Self-Hosted Services

### db.quantum-rishi.com (Supabase)

**Server Requirements:**
- Docker + Docker Compose
- PostgreSQL 15+
- 4GB+ RAM recommended

**Firewall Rules:**
```bash
# Allow only from known IPs
ufw allow from YOUR_APP_SERVER_IP to any port 5432
ufw allow from YOUR_WORKER_IP to any port 5432
```

**SSL Certificate (Let's Encrypt):**
```bash
certbot certonly --standalone -d db.quantum-rishi.com
```

### mail.quantum-rishi.com (MTA)

**Ports:**
- 25 (SMTP)
- 587 (Submission)
- 465 (SMTPS)
- 993 (IMAPS)

**Reverse DNS:**
- Set PTR record at your hosting provider to `mail.quantum-rishi.com`

## Verification

### DNS Propagation

```bash
# Check DNS records
dig app.quantum-rishi.com +short
dig api.quantum-rishi.com +short
dig db.quantum-rishi.com +short
dig mail.quantum-rishi.com +short
dig TXT quantum-rishi.com +short
```

### Email Configuration

```bash
# Test SPF
dig TXT quantum-rishi.com | grep spf

# Test DKIM
dig TXT qr2024._domainkey.quantum-rishi.com

# Test DMARC
dig TXT _dmarc.quantum-rishi.com

# Full email test
curl -X POST https://mail-tester.com/
```

### SSL Verification

```bash
# Check SSL certificate
openssl s_client -connect app.quantum-rishi.com:443 -servername app.quantum-rishi.com
```

## Monitoring

### Cloudflare Analytics

- Dashboard → Analytics → Traffic
- Set up notifications for:
  - DDoS attacks
  - SSL certificate expiry
  - Origin errors

### Health Checks

Set up Cloudflare Health Checks for:
- `https://app.quantum-rishi.com/health`
- `https://api.quantum-rishi.com/health`
- `https://db.quantum-rishi.com/health`

## Troubleshooting

### Common Issues

1. **SSL Error 525 (SSL Handshake Failed)**
   - Ensure origin server has valid SSL certificate
   - Check TLS version compatibility

2. **Error 522 (Connection Timed Out)**
   - Check origin server is reachable
   - Verify firewall allows Cloudflare IPs

3. **Error 524 (A Timeout Occurred)**
   - Origin server taking too long to respond
   - Increase timeout or optimize origin

### Cloudflare IP Ranges

Allow these in your firewall:
- https://www.cloudflare.com/ips-v4
- https://www.cloudflare.com/ips-v6
