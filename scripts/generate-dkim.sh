#!/bin/bash
# DKIM Key Generation Script for QuantumRishi Mail Server
# Generates DKIM keypair and outputs DNS record for Cloudflare

set -euo pipefail

DOMAIN="${1:-quantum-rishi.com}"
SELECTOR="${2:-qr202501}"
KEY_DIR="/etc/opendkim/keys/${DOMAIN}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo "========================================"
echo "  DKIM Key Generation for ${DOMAIN}"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_step "Running without root - keys will be generated in current directory"
    KEY_DIR="./dkim-keys/${DOMAIN}"
fi

# Create directory
mkdir -p "${KEY_DIR}"

log_step "Generating 2048-bit DKIM keypair..."

# Generate private key
openssl genrsa -out "${KEY_DIR}/${SELECTOR}.private" 2048 2>/dev/null

# Generate public key
openssl rsa -in "${KEY_DIR}/${SELECTOR}.private" -pubout -out "${KEY_DIR}/${SELECTOR}.public" 2>/dev/null

# Extract public key for DNS (remove headers and join lines)
PUBLIC_KEY=$(grep -v "^-" "${KEY_DIR}/${SELECTOR}.public" | tr -d '\n')

log_info "Keys generated successfully!"
echo ""

# Set permissions if running as root
if [[ $EUID -eq 0 ]]; then
    chown -R opendkim:opendkim "${KEY_DIR}"
    chmod 700 "${KEY_DIR}"
    chmod 600 "${KEY_DIR}/${SELECTOR}.private"
    chmod 644 "${KEY_DIR}/${SELECTOR}.public"
fi

echo "========================================"
echo -e "${YELLOW}DNS RECORD TO ADD:${NC}"
echo "========================================"
echo ""
echo -e "${GREEN}Record Type:${NC} TXT"
echo -e "${GREEN}Name:${NC} ${SELECTOR}._domainkey"
echo -e "${GREEN}Content:${NC}"
echo ""
echo "v=DKIM1; k=rsa; p=${PUBLIC_KEY}"
echo ""

echo "========================================"
echo -e "${YELLOW}TERRAFORM FORMAT:${NC}"
echo "========================================"
cat << EOF

resource "cloudflare_record" "dkim" {
  zone_id = var.cloudflare_zone_id
  name    = "${SELECTOR}._domainkey"
  type    = "TXT"
  content = "v=DKIM1; k=rsa; p=${PUBLIC_KEY}"
  ttl     = 3600
}
EOF

echo ""
echo "========================================"
echo -e "${YELLOW}OPENDKIM CONFIGURATION:${NC}"
echo "========================================"
echo ""
echo "Add to /etc/opendkim/KeyTable:"
echo "  ${SELECTOR}._domainkey.${DOMAIN} ${DOMAIN}:${SELECTOR}:${KEY_DIR}/${SELECTOR}.private"
echo ""
echo "Add to /etc/opendkim/SigningTable:"
echo "  *@${DOMAIN} ${SELECTOR}._domainkey.${DOMAIN}"
echo ""

echo "========================================"
echo -e "${GREEN}Key files saved to:${NC}"
echo "========================================"
echo "  Private key: ${KEY_DIR}/${SELECTOR}.private"
echo "  Public key:  ${KEY_DIR}/${SELECTOR}.public"
echo ""

# Create a summary file
cat > "${KEY_DIR}/dns-record.txt" << EOF
DKIM DNS Record for ${DOMAIN}
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Selector: ${SELECTOR}

Record Type: TXT
Name: ${SELECTOR}._domainkey
Content: v=DKIM1; k=rsa; p=${PUBLIC_KEY}

Full record name: ${SELECTOR}._domainkey.${DOMAIN}
EOF

log_info "DNS record also saved to: ${KEY_DIR}/dns-record.txt"
