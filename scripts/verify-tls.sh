#!/bin/bash
# TLS Verification Script for QuantumRishi Infrastructure
# Verifies SSL/TLS configuration for all services

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[✓]${NC} $1"; }
log_fail() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_info() { echo -e "[*] $1"; }

# Exit code
EXIT_CODE=0

# Domains to check
DOMAINS=(
    "app.quantum-rishi.com:443"
    "api.quantum-rishi.com:443"
    "mail.quantum-rishi.com:443"
    "mail.quantum-rishi.com:465"  # SMTPS
    "mail.quantum-rishi.com:993"  # IMAPS
)

echo "======================================"
echo "  TLS Verification for QuantumRishi"
echo "======================================"
echo ""

# Check each endpoint
for endpoint in "${DOMAINS[@]}"; do
    IFS=':' read -r host port <<< "$endpoint"
    log_info "Checking ${host}:${port}..."
    
    # Get certificate info
    cert_info=$(echo | timeout 5 openssl s_client -connect "${endpoint}" -servername "${host}" 2>/dev/null)
    
    if [[ -z "$cert_info" ]]; then
        log_fail "${endpoint}: Connection failed"
        EXIT_CODE=1
        continue
    fi
    
    # Check certificate validity
    not_after=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$not_after" ]]; then
        not_after_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_after" +%s)
        now_epoch=$(date +%s)
        days_left=$(( (not_after_epoch - now_epoch) / 86400 ))
        
        if [[ $days_left -lt 0 ]]; then
            log_fail "${endpoint}: Certificate EXPIRED"
            EXIT_CODE=1
        elif [[ $days_left -lt 14 ]]; then
            log_warn "${endpoint}: Certificate expires in ${days_left} days"
        else
            log_pass "${endpoint}: Certificate valid (${days_left} days left)"
        fi
    fi
    
    # Check TLS version
    for tls_ver in "tls1" "tls1_1"; do
        if echo | timeout 3 openssl s_client -connect "${endpoint}" -servername "${host}" -${tls_ver} 2>/dev/null | grep -q "CONNECTED"; then
            log_warn "${endpoint}: Insecure protocol ${tls_ver} enabled"
        fi
    done
    
    # Check TLS 1.2/1.3 support
    if echo | timeout 3 openssl s_client -connect "${endpoint}" -servername "${host}" -tls1_2 2>/dev/null | grep -q "CONNECTED"; then
        log_pass "${endpoint}: TLS 1.2 supported"
    fi
    
    if echo | timeout 3 openssl s_client -connect "${endpoint}" -servername "${host}" -tls1_3 2>/dev/null | grep -q "CONNECTED"; then
        log_pass "${endpoint}: TLS 1.3 supported"
    fi
    
    # Check certificate chain
    chain_count=$(echo "$cert_info" | grep -c "BEGIN CERTIFICATE" || true)
    if [[ $chain_count -ge 2 ]]; then
        log_pass "${endpoint}: Full certificate chain present (${chain_count} certs)"
    else
        log_warn "${endpoint}: Incomplete certificate chain"
    fi
    
    echo ""
done

# Check SMTP STARTTLS
log_info "Checking SMTP STARTTLS on mail.quantum-rishi.com:587..."
smtp_tls=$(echo -e "EHLO test\nSTARTTLS\nQUIT" | timeout 5 openssl s_client -connect "mail.quantum-rishi.com:587" -starttls smtp 2>/dev/null || true)
if echo "$smtp_tls" | grep -q "CONNECTED"; then
    log_pass "SMTP STARTTLS working on port 587"
else
    log_fail "SMTP STARTTLS failed on port 587"
    EXIT_CODE=1
fi

echo ""

# Check MTA-STS
log_info "Checking MTA-STS configuration..."
mta_sts=$(dig TXT _mta-sts.quantum-rishi.com +short 2>/dev/null || true)
if [[ "$mta_sts" == *"v=STSv1"* ]]; then
    log_pass "MTA-STS DNS record present"
else
    log_warn "MTA-STS DNS record missing"
fi

# Check TLSRPT
tlsrpt=$(dig TXT _smtp._tls.quantum-rishi.com +short 2>/dev/null || true)
if [[ "$tlsrpt" == *"v=TLSRPTv1"* ]]; then
    log_pass "TLSRPT DNS record present"
else
    log_warn "TLSRPT DNS record missing"
fi

echo ""
echo "======================================"
if [[ $EXIT_CODE -eq 0 ]]; then
    log_pass "All TLS checks passed!"
else
    log_fail "Some TLS checks failed"
fi
echo "======================================"

exit $EXIT_CODE
