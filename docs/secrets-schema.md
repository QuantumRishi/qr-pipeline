# Environment Secrets Schema

Definition of secrets required for each deployment environment.

## Organization Secrets

| Secret | Description | Rotation |
|--------|-------------|----------|
| `QR_BOT_PAT` | GitHub PAT for qr-bot machine user | 90 days |
| `SLACK_WEBHOOK_URL` | Slack notifications webhook | As needed |
| `DISCORD_WEBHOOK_URL` | Discord notifications webhook | As needed |
| `NPM_TOKEN` | NPM publish token | 90 days |

## Repository Secrets

### All Repositories

| Secret | Description |
|--------|-------------|
| `CODECOV_TOKEN` | Codecov upload token |

### qr.dev / Apps

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anonymous key |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |

### Workers / Edge

| Secret | Description |
|--------|-------------|
| `CLOUDFLARE_API_TOKEN` | CF API token (Workers write) |
| `CLOUDFLARE_ACCOUNT_ID` | CF account ID |

### qr-mail

| Secret | Description |
|--------|-------------|
| `RESEND_API_KEY` | Resend transactional email API |

## Environment Variables

### Development

```yaml
NODE_ENV: development
DEBUG: "qr:*"
LOG_LEVEL: debug
SUPABASE_URL: http://localhost:54321
```

### Staging

```yaml
NODE_ENV: staging
LOG_LEVEL: info
SUPABASE_URL: https://staging-xyz.supabase.co
```

### Production

```yaml
NODE_ENV: production
LOG_LEVEL: warn
SUPABASE_URL: https://prod-xyz.supabase.co
```

## Vault Secret Paths

All production secrets stored in HashiCorp Vault:

```
secret/
├── qr/
│   ├── dev/
│   │   ├── supabase          # Supabase keys
│   │   ├── cloudflare        # CF API token
│   │   └── jwt               # JWT secrets
│   ├── staging/
│   │   ├── supabase
│   │   ├── cloudflare
│   │   └── jwt
│   └── prod/
│       ├── supabase
│       ├── cloudflare
│       ├── jwt
│       └── db                # Database credentials
├── transit/
│   └── qr-encrypt          # Encryption key
└── pki/
    └── qr-internal         # Internal TLS certs
```

## Secret Rotation

### Automated

- Vault dynamic secrets: Automatic rotation
- JWT signing keys: Rotated weekly via `qr-db/bin/rotate-keys`

### Manual

- GitHub PATs: 90-day rotation reminder
- API keys: Rotate on personnel change

## Adding New Secrets

1. Add to Vault (production):
   ```bash
   vault kv put secret/qr/prod/new-service api_key="..."
   ```

2. Add to GitHub (dev/staging):
   ```bash
   gh secret set NEW_SERVICE_KEY --org QuantumRishi
   ```

3. Document in this file

4. Update relevant workflows
