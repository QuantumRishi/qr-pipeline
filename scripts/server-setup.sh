#!/bin/bash
# Unified Server Setup Script for QuantumRishi Infrastructure
# One-command setup for self-hosted runner, mail server, and monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="quantum-rishi.com"
RUNNER_USER="runner"
MAIL_USER="mail"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_header() { echo -e "\n${CYAN}════════════════════════════════════════${NC}\n${CYAN}  $1${NC}\n${CYAN}════════════════════════════════════════${NC}\n"; }

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS"
        exit 1
    fi
    log_info "Detected OS: $OS $VERSION"
}

# Install base packages
install_base() {
    log_header "Installing Base Packages"
    
    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                curl wget git jq unzip \
                build-essential \
                ca-certificates \
                gnupg lsb-release \
                ufw fail2ban \
                htop iotop \
                certbot
            ;;
        fedora|rhel|centos|rocky|almalinux)
            dnf install -y \
                curl wget git jq unzip \
                gcc gcc-c++ make \
                ca-certificates \
                firewalld fail2ban \
                htop iotop \
                certbot
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    log_info "Base packages installed"
}

# Configure firewall
setup_firewall() {
    log_header "Configuring Firewall"
    
    case $OS in
        ubuntu|debian)
            ufw --force reset
            ufw default deny incoming
            ufw default allow outgoing
            
            # SSH
            ufw allow 22/tcp comment 'SSH'
            
            # HTTP/HTTPS
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'
            
            # Mail
            ufw allow 25/tcp comment 'SMTP'
            ufw allow 587/tcp comment 'SMTP Submission'
            ufw allow 993/tcp comment 'IMAPS'
            
            ufw --force enable
            ;;
        fedora|rhel|centos|rocky|almalinux)
            systemctl enable --now firewalld
            
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --permanent --add-service=smtp
            firewall-cmd --permanent --add-port=587/tcp
            firewall-cmd --permanent --add-service=imaps
            
            firewall-cmd --reload
            ;;
    esac
    
    log_info "Firewall configured"
}

# Setup fail2ban
setup_fail2ban() {
    log_header "Configuring Fail2Ban"
    
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3

[postfix]
enabled = true
port = smtp,465,587
logpath = %(postfix_log)s

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps
logpath = %(dovecot_log)s
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_info "Fail2ban configured"
}

# Install and setup GitHub Actions runner
setup_runner() {
    log_header "Setting Up GitHub Actions Runner"
    
    local RUNNER_VERSION="2.321.0"
    local RUNNER_ARCH="linux-x64"
    
    # Create runner user
    if ! id "$RUNNER_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$RUNNER_USER"
        log_info "Created user: $RUNNER_USER"
    fi
    
    # Create runner directory
    local RUNNER_DIR="/opt/actions-runner"
    mkdir -p "$RUNNER_DIR"
    
    # Download runner
    cd "$RUNNER_DIR"
    curl -sL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" | tar xz
    
    # Set ownership
    chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"
    
    # Install dependencies
    ./bin/installdependencies.sh
    
    log_info "Runner binaries installed to $RUNNER_DIR"
    
    # Create systemd service
    cat > /etc/systemd/system/github-runner.service << EOF
[Unit]
Description=GitHub Actions Self-Hosted Runner
After=network.target

[Service]
Type=simple
User=${RUNNER_USER}
Group=${RUNNER_USER}
WorkingDirectory=${RUNNER_DIR}
ExecStart=${RUNNER_DIR}/run.sh
Restart=always
RestartSec=10
KillMode=process
KillSignal=SIGTERM
TimeoutStopSec=5min

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${RUNNER_DIR} /tmp /var/tmp
PrivateTmp=yes

# Resource limits
MemoryMax=4G
CPUQuota=80%

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    
    log_info "Runner systemd service created"
    
    echo ""
    log_warn "To complete runner setup, run as ${RUNNER_USER}:"
    echo "  sudo -u ${RUNNER_USER} ${RUNNER_DIR}/config.sh \\"
    echo "    --url https://github.com/QuantumRishi \\"
    echo "    --token <RUNNER_TOKEN> \\"
    echo "    --name qr-runner-1 \\"
    echo "    --labels qr,secure,no-docker \\"
    echo "    --work _work \\"
    echo "    --unattended"
    echo ""
    echo "Get token from: https://github.com/organizations/QuantumRishi/settings/actions/runners/new"
}

# Install mail server components
setup_mail_server() {
    log_header "Setting Up Mail Server"
    
    # Install packages
    case $OS in
        ubuntu|debian)
            DEBIAN_FRONTEND=noninteractive apt-get install -y \
                postfix postfix-policyd-spf-python \
                dovecot-imapd dovecot-lmtpd \
                opendkim opendkim-tools \
                rspamd redis-server
            ;;
        fedora|rhel|centos|rocky|almalinux)
            dnf install -y \
                postfix postfix-policyd-spf-python \
                dovecot \
                opendkim opendkim-tools \
                rspamd redis
            ;;
    esac
    
    log_info "Mail packages installed"
    
    # Copy configuration files
    if [[ -d "${SCRIPT_DIR}/../infrastructure/mail" ]]; then
        cp "${SCRIPT_DIR}/../infrastructure/mail/postfix/main.cf" /etc/postfix/main.cf
        cp "${SCRIPT_DIR}/../infrastructure/mail/postfix/master.cf" /etc/postfix/master.cf
        cp "${SCRIPT_DIR}/../infrastructure/mail/dovecot/dovecot.conf" /etc/dovecot/dovecot.conf
        
        mkdir -p /etc/opendkim /etc/opendkim/keys
        cp "${SCRIPT_DIR}/../infrastructure/mail/opendkim/"* /etc/opendkim/
        
        log_info "Mail configuration files copied"
    else
        log_warn "Mail config files not found - manual configuration required"
    fi
    
    # Create mail directories
    mkdir -p /var/mail/vhosts/"${DOMAIN}"
    
    # Create mail user
    if ! id "$MAIL_USER" &>/dev/null; then
        groupadd -g 5000 vmail
        useradd -g vmail -u 5000 -d /var/mail vmail
    fi
    
    chown -R vmail:vmail /var/mail
    
    log_info "Mail server directories created"
}

# Setup SSL certificates
setup_ssl() {
    log_header "Setting Up SSL Certificates"
    
    local EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
    
    # Get certificates for mail server
    certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        -d "mail.${DOMAIN}" \
        --preferred-challenges http
    
    log_info "SSL certificate obtained for mail.${DOMAIN}"
    
    # Setup auto-renewal
    cat > /etc/systemd/system/certbot-renewal.service << 'EOF'
[Unit]
Description=Certbot Renewal

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "/opt/scripts/ssl-renewal-hook.sh"
EOF
    
    cat > /etc/systemd/system/certbot-renewal.timer << 'EOF'
[Unit]
Description=Run certbot twice daily

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Create renewal hook
    mkdir -p /opt/scripts
    cat > /opt/scripts/ssl-renewal-hook.sh << 'EOF'
#!/bin/bash
systemctl reload postfix
systemctl reload dovecot
EOF
    chmod +x /opt/scripts/ssl-renewal-hook.sh
    
    systemctl daemon-reload
    systemctl enable --now certbot-renewal.timer
    
    log_info "SSL auto-renewal configured"
}

# Generate DKIM keys
setup_dkim() {
    log_header "Generating DKIM Keys"
    
    local SELECTOR="qr$(date +%Y%m)"
    local KEY_DIR="/etc/opendkim/keys/${DOMAIN}"
    
    mkdir -p "$KEY_DIR"
    
    # Generate keys
    opendkim-genkey -b 2048 -d "$DOMAIN" -D "$KEY_DIR" -s "$SELECTOR" -v
    
    # Set permissions
    chown -R opendkim:opendkim /etc/opendkim
    chmod 700 "$KEY_DIR"
    chmod 600 "$KEY_DIR/${SELECTOR}.private"
    
    # Update OpenDKIM config
    echo "${SELECTOR}._domainkey.${DOMAIN} ${DOMAIN}:${SELECTOR}:${KEY_DIR}/${SELECTOR}.private" > /etc/opendkim/KeyTable
    echo "*@${DOMAIN} ${SELECTOR}._domainkey.${DOMAIN}" > /etc/opendkim/SigningTable
    
    log_info "DKIM keys generated"
    
    echo ""
    echo "Add this DNS TXT record:"
    echo "  Name: ${SELECTOR}._domainkey"
    cat "$KEY_DIR/${SELECTOR}.txt"
}

# Start all services
start_services() {
    log_header "Starting Services"
    
    # Enable and start services
    local services=(
        "postfix"
        "dovecot"
        "opendkim"
        "rspamd"
        "redis"
    )
    
    for svc in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            systemctl enable "$svc"
            systemctl restart "$svc"
            log_info "Started: $svc"
        fi
    done
}

# Run verification
verify_setup() {
    log_header "Verifying Setup"
    
    echo "Service Status:"
    echo "─────────────────────────────────────────"
    
    local services=("postfix" "dovecot" "opendkim" "rspamd" "fail2ban")
    
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} $svc: running"
        else
            echo -e "  ${RED}○${NC} $svc: not running"
        fi
    done
    
    echo ""
    echo "Ports Listening:"
    echo "─────────────────────────────────────────"
    ss -tlnp | grep -E ':(22|25|80|443|587|993) ' || true
    
    echo ""
    echo "Firewall Rules:"
    echo "─────────────────────────────────────────"
    case $OS in
        ubuntu|debian)
            ufw status numbered
            ;;
        *)
            firewall-cmd --list-all
            ;;
    esac
}

# Print summary
print_summary() {
    log_header "Setup Complete!"
    
    cat << EOF
Next Steps:
───────────────────────────────────────────────────

1. Configure GitHub Runner:
   sudo -u runner /opt/actions-runner/config.sh \\
     --url https://github.com/QuantumRishi \\
     --token <GET_FROM_GITHUB> \\
     --labels qr,secure,no-docker

2. Start Runner:
   sudo systemctl enable --now github-runner

3. Add DKIM DNS Record:
   Check /etc/opendkim/keys/${DOMAIN}/*.txt

4. Test Email:
   echo "Test" | mail -s "Test" your@email.com

5. Verify TLS:
   openssl s_client -connect mail.${DOMAIN}:993

───────────────────────────────────────────────────
Documentation: https://github.com/QuantumRishi/qr-pipeline/docs
EOF
}

# Main menu
main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    detect_os
    
    echo ""
    echo "QuantumRishi Server Setup"
    echo "═════════════════════════════════════════"
    echo ""
    echo "This script will install and configure:"
    echo "  • GitHub Actions self-hosted runner"
    echo "  • Postfix + Dovecot mail server"
    echo "  • OpenDKIM + Rspamd"
    echo "  • SSL certificates (Let's Encrypt)"
    echo "  • Firewall + Fail2Ban"
    echo ""
    
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    install_base
    setup_firewall
    setup_fail2ban
    setup_runner
    setup_mail_server
    setup_ssl
    setup_dkim
    start_services
    verify_setup
    print_summary
}

# Allow running individual functions
if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [function]"
    echo ""
    echo "Functions:"
    echo "  install_base     - Install base packages"
    echo "  setup_firewall   - Configure firewall"
    echo "  setup_fail2ban   - Configure fail2ban"
    echo "  setup_runner     - Install GitHub runner"
    echo "  setup_mail_server - Install mail server"
    echo "  setup_ssl        - Get SSL certificates"
    echo "  setup_dkim       - Generate DKIM keys"
    echo "  start_services   - Start all services"
    echo "  verify_setup     - Verify installation"
    echo ""
    echo "Run without arguments for full setup."
    exit 0
elif [[ -n "${1:-}" ]]; then
    detect_os
    "$1"
else
    main
fi
