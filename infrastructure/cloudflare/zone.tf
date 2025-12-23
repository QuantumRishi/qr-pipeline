# Cloudflare Zone Configuration for quantum-rishi.com
# Terraform module for DNS records and security settings

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "zone_id" {
  description = "Cloudflare zone ID for quantum-rishi.com"
  type        = string
}

variable "server_ip" {
  description = "Self-hosted server IP address"
  type        = string
}

variable "mail_ip" {
  description = "Mail server IP address"
  type        = string
}

variable "dkim_public_key" {
  description = "DKIM public key (without header/footer)"
  type        = string
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ─────────────────────────────────────────────────────────────────────────────
# A Records - Direct IP mappings
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "apex" {
  zone_id = var.zone_id
  name    = "@"
  type    = "A"
  content = var.server_ip
  proxied = false
  ttl     = 300
  comment = "Apex domain - self-hosted server"
}

resource "cloudflare_record" "db" {
  zone_id = var.zone_id
  name    = "db"
  type    = "A"
  content = var.server_ip
  proxied = false
  ttl     = 300
  comment = "Supabase/PostgreSQL - not proxied for direct DB connections"
}

resource "cloudflare_record" "mail" {
  zone_id = var.zone_id
  name    = "mail"
  type    = "A"
  content = var.mail_ip
  proxied = false
  ttl     = 300
  comment = "Mail server - not proxied for SMTP"
}

# ─────────────────────────────────────────────────────────────────────────────
# CNAME Records - Cloudflare services
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "app" {
  zone_id = var.zone_id
  name    = "app"
  type    = "CNAME"
  content = "qr-dev.pages.dev"
  proxied = true
  comment = "Cloudflare Pages - qr.dev frontend"
}

resource "cloudflare_record" "api" {
  zone_id = var.zone_id
  name    = "api"
  type    = "CNAME"
  content = "qr-api.workers.dev"
  proxied = true
  comment = "Cloudflare Workers - API middleware"
}

resource "cloudflare_record" "docs" {
  zone_id = var.zone_id
  name    = "docs"
  type    = "CNAME"
  content = "quantumrishi.github.io"
  proxied = true
  comment = "GitHub Pages - documentation"
}

# ─────────────────────────────────────────────────────────────────────────────
# MX Records - Email routing
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "mx_primary" {
  zone_id  = var.zone_id
  name     = "@"
  type     = "MX"
  content  = "mail.quantum-rishi.com"
  priority = 10
  comment  = "Primary mail server"
}

resource "cloudflare_record" "mx_backup" {
  zone_id  = var.zone_id
  name     = "@"
  type     = "MX"
  content  = "mail.quantum-rishi.com"
  priority = 20
  comment  = "Backup mail server (same host)"
}

# ─────────────────────────────────────────────────────────────────────────────
# TXT Records - Email authentication
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "spf" {
  zone_id = var.zone_id
  name    = "@"
  type    = "TXT"
  content = "v=spf1 mx ip4:${var.mail_ip} -all"
  comment = "SPF - Sender Policy Framework"
}

resource "cloudflare_record" "dmarc" {
  zone_id = var.zone_id
  name    = "_dmarc"
  type    = "TXT"
  content = "v=DMARC1; p=reject; rua=mailto:dmarc-reports@quantum-rishi.com; ruf=mailto:dmarc-forensics@quantum-rishi.com; sp=reject; adkim=s; aspf=s"
  comment = "DMARC - reject policy with reporting"
}

resource "cloudflare_record" "dkim" {
  zone_id = var.zone_id
  name    = "qr2024._domainkey"
  type    = "TXT"
  content = "v=DKIM1; k=rsa; p=${var.dkim_public_key}"
  comment = "DKIM - DomainKeys Identified Mail"
}

# MTA-STS policy record
resource "cloudflare_record" "mta_sts" {
  zone_id = var.zone_id
  name    = "_mta-sts"
  type    = "TXT"
  content = "v=STSv1; id=20241223001"
  comment = "MTA-STS policy version"
}

# TLSRPT - TLS Reporting
resource "cloudflare_record" "tlsrpt" {
  zone_id = var.zone_id
  name    = "_smtp._tls"
  type    = "TXT"
  content = "v=TLSRPTv1; rua=mailto:tlsrpt@quantum-rishi.com"
  comment = "TLS-RPT - SMTP TLS Reporting"
}

# ─────────────────────────────────────────────────────────────────────────────
# CAA Records - Certificate Authority Authorization
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "caa_issue" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  data {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org"
  }
  comment = "Allow Let's Encrypt to issue certificates"
}

resource "cloudflare_record" "caa_issuewild" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  data {
    flags = 0
    tag   = "issuewild"
    value = "letsencrypt.org"
  }
  comment = "Allow Let's Encrypt to issue wildcard certificates"
}

resource "cloudflare_record" "caa_iodef" {
  zone_id = var.zone_id
  name    = "@"
  type    = "CAA"
  data {
    flags = 0
    tag   = "iodef"
    value = "mailto:security@quantum-rishi.com"
  }
  comment = "CAA violation reporting email"
}

# ─────────────────────────────────────────────────────────────────────────────
# Zone Settings
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_zone_settings_override" "settings" {
  zone_id = var.zone_id

  settings {
    ssl                      = "strict"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    automatic_https_rewrites = "on"
    tls_1_3                  = "on"
    http3                    = "on"
    zero_rtt                 = "on"
    security_level           = "high"
    browser_check            = "on"
    email_obfuscation        = "on"
    server_side_exclude      = "on"
    hotlink_protection       = "on"
    brotli                   = "on"
    minify {
      css  = "on"
      html = "on"
      js   = "on"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────────────────────────────────────

output "dns_records" {
  description = "Created DNS records"
  value = {
    apex = cloudflare_record.apex.hostname
    app  = cloudflare_record.app.hostname
    api  = cloudflare_record.api.hostname
    db   = cloudflare_record.db.hostname
    mail = cloudflare_record.mail.hostname
    docs = cloudflare_record.docs.hostname
  }
}
