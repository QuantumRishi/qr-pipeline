#!/bin/bash
# Let's Encrypt Certificate Setup for mail.quantum-rishi.com
# Run on the mail server

set -euo pipefail

DOMAIN="mail.quantum-rishi.com"
EMAIL="admin@quantum-rishi.com"
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    log_info "Installing certbot"
    apt-get update
    apt-get install -y certbot python3-certbot-dns-cloudflare
fi

# Check if certificate already exists
if [[ -d "${CERT_PATH}" ]]; then
    log_info "Certificate already exists at ${CERT_PATH}"
    log_info "Checking expiration..."
    openssl x509 -enddate -noout -in "${CERT_PATH}/cert.pem"
    
    read -p "Do you want to renew? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Option 1: Standalone (requires ports 80/443 free)
obtain_standalone() {
    log_info "Obtaining certificate using standalone method"
    
    # Stop services temporarily
    systemctl stop postfix dovecot 2>/dev/null || true
    
    certbot certonly \
        --standalone \
        --preferred-challenges http \
        -d "${DOMAIN}" \
        --email "${EMAIL}" \
        --agree-tos \
        --non-interactive
    
    # Restart services
    systemctl start postfix dovecot
}

# Option 2: DNS challenge with Cloudflare
obtain_cloudflare() {
    log_info "Obtaining certificate using Cloudflare DNS challenge"
    
    # Create Cloudflare credentials file
    CF_CREDS="/root/.cloudflare-credentials"
    if [[ ! -f "${CF_CREDS}" ]]; then
        log_warn "Cloudflare credentials not found"
        echo "Create ${CF_CREDS} with:"
        echo "  dns_cloudflare_api_token = YOUR_API_TOKEN"
        exit 1
    fi
    
    chmod 600 "${CF_CREDS}"
    
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "${CF_CREDS}" \
        -d "${DOMAIN}" \
        --email "${EMAIL}" \
        --agree-tos \
        --non-interactive
}

# Choose method
if [[ -f "/root/.cloudflare-credentials" ]]; then
    obtain_cloudflare
else
    obtain_standalone
fi

# Verify certificate
if [[ -f "${CERT_PATH}/fullchain.pem" ]]; then
    log_info "Certificate obtained successfully!"
    
    # Show certificate info
    openssl x509 -in "${CERT_PATH}/fullchain.pem" -noout -subject -dates
    
    # Set permissions
    chmod 755 /etc/letsencrypt/{live,archive}
    chmod 644 "${CERT_PATH}/fullchain.pem"
    chmod 640 "${CERT_PATH}/privkey.pem"
    chgrp ssl-cert "${CERT_PATH}/privkey.pem"
    
    # Add services to ssl-cert group
    usermod -a -G ssl-cert postfix
    usermod -a -G ssl-cert dovecot
    
    log_info "Reloading services..."
    systemctl reload postfix
    systemctl reload dovecot
    
    log_info "Certificate setup complete!"
else
    log_error "Certificate generation failed"
    exit 1
fi
