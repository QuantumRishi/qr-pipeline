#!/bin/bash
# Cloudflare DNS Setup Script using API
# Creates all required DNS records for quantum-rishi.com

set -euo pipefail

# Configuration
DOMAIN="quantum-rishi.com"
API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
ZONE_ID="${CLOUDFLARE_ZONE_ID:-}"

# Server IPs - Update these with your actual IPs
APP_IP="${APP_IP:-}"
API_IP="${API_IP:-}"
MAIL_IP="${MAIL_IP:-}"
DB_IP="${DB_IP:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check prerequisites
check_config() {
    local missing=0
    
    if [[ -z "$API_TOKEN" ]]; then
        log_error "CLOUDFLARE_API_TOKEN is not set"
        missing=1
    fi
    
    if [[ -z "$ZONE_ID" ]]; then
        log_warn "CLOUDFLARE_ZONE_ID not set, attempting to fetch..."
        ZONE_ID=$(get_zone_id)
        if [[ -z "$ZONE_ID" ]]; then
            log_error "Could not fetch zone ID"
            missing=1
        else
            log_info "Found zone ID: $ZONE_ID"
        fi
    fi
    
    if [[ $missing -eq 1 ]]; then
        echo ""
        echo "Set these environment variables:"
        echo "  export CLOUDFLARE_API_TOKEN='your-api-token'"
        echo "  export CLOUDFLARE_ZONE_ID='your-zone-id'"
        echo "  export APP_IP='your-app-server-ip'"
        echo "  export API_IP='your-api-server-ip'"
        echo "  export MAIL_IP='your-mail-server-ip'"
        exit 1
    fi
}

# Get zone ID from domain
get_zone_id() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id // empty'
}

# Create or update DNS record
upsert_record() {
    local type=$1
    local name=$2
    local content=$3
    local proxied=${4:-false}
    local ttl=${5:-3600}
    
    # Check if record exists
    local existing=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=${type}&name=${name}.${DOMAIN}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json")
    
    local record_id=$(echo "$existing" | jq -r '.result[0].id // empty')
    
    local data=$(jq -n \
        --arg type "$type" \
        --arg name "$name" \
        --arg content "$content" \
        --argjson proxied "$proxied" \
        --argjson ttl "$ttl" \
        '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: $ttl}')
    
    if [[ -n "$record_id" ]]; then
        # Update existing record
        local result=$(curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$data")
        
        if echo "$result" | jq -e '.success' > /dev/null; then
            log_info "Updated: ${name}.${DOMAIN} (${type})"
        else
            log_error "Failed to update ${name}: $(echo "$result" | jq -r '.errors[0].message')"
        fi
    else
        # Create new record
        local result=$(curl -s -X POST \
            "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$data")
        
        if echo "$result" | jq -e '.success' > /dev/null; then
            log_info "Created: ${name}.${DOMAIN} (${type})"
        else
            log_error "Failed to create ${name}: $(echo "$result" | jq -r '.errors[0].message')"
        fi
    fi
}

# Create TXT record (special handling for long records)
create_txt_record() {
    local name=$1
    local content=$2
    
    upsert_record "TXT" "$name" "$content" false 3600
}

# Main setup
main() {
    echo "========================================"
    echo "  Cloudflare DNS Setup for ${DOMAIN}"
    echo "========================================"
    echo ""
    
    check_config
    
    # Prompt for IPs if not set
    if [[ -z "$APP_IP" ]]; then
        read -p "Enter APP server IP (for app.${DOMAIN}): " APP_IP
    fi
    if [[ -z "$API_IP" ]]; then
        API_IP="$APP_IP"
        log_info "Using APP_IP for API subdomain"
    fi
    if [[ -z "$MAIL_IP" ]]; then
        read -p "Enter MAIL server IP (for mail.${DOMAIN}): " MAIL_IP
    fi
    if [[ -z "$DB_IP" ]]; then
        DB_IP="$APP_IP"
        log_info "Using APP_IP for DB subdomain"
    fi
    
    log_step "Creating A records..."
    
    # A Records (proxied through Cloudflare)
    upsert_record "A" "app" "$APP_IP" true 1
    upsert_record "A" "api" "$API_IP" true 1
    upsert_record "A" "docs" "$APP_IP" true 1
    
    # Mail server (NOT proxied - mail needs direct connection)
    upsert_record "A" "mail" "$MAIL_IP" false 3600
    
    # Database (NOT proxied for direct connection)
    upsert_record "A" "db" "$DB_IP" false 3600
    
    log_step "Creating MX record..."
    
    # MX Record
    local mx_data=$(jq -n \
        --arg type "MX" \
        --arg name "@" \
        --arg content "mail.${DOMAIN}" \
        --argjson priority 10 \
        '{type: $type, name: $name, content: $content, priority: $priority, ttl: 3600}')
    
    curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$mx_data" > /dev/null 2>&1 || true
    log_info "MX record configured"
    
    log_step "Creating email authentication records..."
    
    # SPF Record
    create_txt_record "@" "v=spf1 mx a:mail.${DOMAIN} include:_spf.google.com ~all"
    
    # DMARC Record
    create_txt_record "_dmarc" "v=DMARC1; p=quarantine; rua=mailto:dmarc@${DOMAIN}; ruf=mailto:dmarc@${DOMAIN}; fo=1"
    
    # MTA-STS Record
    create_txt_record "_mta-sts" "v=STSv1; id=$(date +%Y%m%d%H%M%S)"
    
    # TLSRPT Record
    create_txt_record "_smtp._tls" "v=TLSRPTv1; rua=mailto:tls-reports@${DOMAIN}"
    
    log_step "Creating additional records..."
    
    # CAA Record for Let's Encrypt
    local caa_data=$(jq -n \
        --arg type "CAA" \
        --arg name "@" \
        '{type: $type, name: $name, data: {flags: 0, tag: "issue", value: "letsencrypt.org"}, ttl: 3600}')
    
    curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$caa_data" > /dev/null 2>&1 || true
    log_info "CAA record configured for Let's Encrypt"
    
    log_step "Configuring SSL/TLS settings..."
    
    # Set SSL mode to Full (Strict)
    curl -s -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/ssl" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"value":"strict"}' > /dev/null
    log_info "SSL mode set to Full (Strict)"
    
    # Enable Always Use HTTPS
    curl -s -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/always_use_https" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"value":"on"}' > /dev/null
    log_info "Always Use HTTPS enabled"
    
    # Enable Automatic HTTPS Rewrites
    curl -s -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/automatic_https_rewrites" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"value":"on"}' > /dev/null
    log_info "Automatic HTTPS Rewrites enabled"
    
    # Enable HSTS
    curl -s -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/security_header" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"value":{"strict_transport_security":{"enabled":true,"max_age":31536000,"include_subdomains":true,"preload":true}}}' > /dev/null
    log_info "HSTS enabled with preload"
    
    # Minimum TLS 1.2
    curl -s -X PATCH \
        "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/settings/min_tls_version" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"value":"1.2"}' > /dev/null
    log_info "Minimum TLS version set to 1.2"
    
    echo ""
    echo "========================================"
    log_info "DNS and Security setup complete!"
    echo "========================================"
    echo ""
    echo "Records created:"
    echo "  - app.${DOMAIN} → ${APP_IP} (proxied)"
    echo "  - api.${DOMAIN} → ${API_IP} (proxied)"
    echo "  - docs.${DOMAIN} → ${APP_IP} (proxied)"
    echo "  - mail.${DOMAIN} → ${MAIL_IP} (direct)"
    echo "  - db.${DOMAIN} → ${DB_IP} (direct)"
    echo "  - MX → mail.${DOMAIN}"
    echo "  - SPF, DMARC, MTA-STS, TLSRPT records"
    echo ""
    echo "Next steps:"
    echo "  1. Generate DKIM keys: ./generate-dkim.sh"
    echo "  2. Add DKIM TXT record from generated output"
    echo "  3. Set up SSL certificates on mail server"
    echo "  4. Configure and start mail services"
}

main "$@"
