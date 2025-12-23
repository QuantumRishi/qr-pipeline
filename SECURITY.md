# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

Email: security@quantumrishi.dev

**Do NOT open public issues for security vulnerabilities.**

## Security Practices

### Action Pinning
- All external actions MUST be SHA-pinned
- Run `./scripts/verify-pins.sh` to validate

### Secrets
- Never echo secrets in logs
- Use `::add-mask::` for dynamic secrets
- Prefer OIDC over long-lived tokens

### Runner Hardening
- All jobs include step-security/harden-runner
- Egress policy set to audit (block in production)
