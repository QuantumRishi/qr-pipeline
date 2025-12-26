#!/bin/bash
# QuantumRishi Production Server Provisioning Script
# Run this on your Ubuntu/Debian server: bash server-provision.sh
# Server IP: 45.112.28.26

set -euo pipefail

DOMAIN="quantum-rishi.com"
MAIL_DOMAIN="mail.quantum-rishi.com"
DKIM_SELECTOR="qr202501"
ADMIN_EMAIL="admin@quantum-rishi.com"
RUNNER_USER="github-runner"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

echo "========================================"
echo "  QuantumRishi Server Provisioning"
echo "  Domain: ${DOMAIN}"
echo "========================================"
echo ""

# ============================================
# STEP 1: System Update and Base Packages
# ============================================
log_step "1. Updating system and installing base packages..."

apt-get update && apt-get upgrade -y
apt-get install -y \
    curl wget git vim htop unzip \
    ufw fail2ban \
    nginx certbot python3-certbot-nginx \
    postfix postfix-policyd-spf-python dovecot-core dovecot-imapd dovecot-pop3d \
    opendkim opendkim-tools \
    rspamd redis-server \
    docker.io docker-compose \
    jq

log_info "Base packages installed"

# ============================================
# STEP 2: Configure Firewall
# ============================================
log_step "2. Configuring UFW firewall..."

ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 25/tcp    # SMTP
ufw allow 465/tcp   # SMTPS
ufw allow 587/tcp   # Submission
ufw allow 993/tcp   # IMAPS
ufw allow 995/tcp   # POP3S

echo "y" | ufw enable
log_info "Firewall configured"

# ============================================
# STEP 3: Configure Fail2Ban
# ============================================
log_step "3. Configuring Fail2Ban..."

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log

[postfix]
enabled = true
port = smtp,465,submission
filter = postfix
logpath = /var/log/mail.log

[dovecot]
enabled = true
port = imap,imaps,pop3,pop3s
filter = dovecot
logpath = /var/log/mail.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log_info "Fail2Ban configured"

# ============================================
# STEP 4: Configure Nginx
# ============================================
log_step "4. Configuring Nginx..."

# Main site config
cat > /etc/nginx/sites-available/${DOMAIN} << EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};
    
    # SSL will be configured by certbot
    
    root /var/www/${DOMAIN};
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}
EOF

# App subdomain
cat > /etc/nginx/sites-available/app.${DOMAIN} << EOF
server {
    listen 80;
    server_name app.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.${DOMAIN};
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# API subdomain
cat > /etc/nginx/sites-available/api.${DOMAIN} << EOF
server {
    listen 80;
    server_name api.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.${DOMAIN};
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Docs subdomain
cat > /etc/nginx/sites-available/docs.${DOMAIN} << EOF
server {
    listen 80;
    server_name docs.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name docs.${DOMAIN};
    
    root /var/www/docs.${DOMAIN};
    index index.html;
    
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

# Create web roots
mkdir -p /var/www/${DOMAIN}
mkdir -p /var/www/docs.${DOMAIN}
mkdir -p /var/www/certbot

# Create placeholder pages
echo "<html><head><title>QuantumRishi</title></head><body><h1>Welcome to QuantumRishi</h1><p>Production server is live!</p></body></html>" > /var/www/${DOMAIN}/index.html
echo "<html><head><title>QuantumRishi Docs</title></head><body><h1>Documentation</h1><p>Coming soon...</p></body></html>" > /var/www/docs.${DOMAIN}/index.html

# Enable sites
ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/app.${DOMAIN} /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/api.${DOMAIN} /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/docs.${DOMAIN} /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
log_info "Nginx configured"

# ============================================
# STEP 5: SSL Certificates (Let's Encrypt)
# ============================================
log_step "5. Obtaining SSL certificates..."

certbot --nginx -d ${DOMAIN} -d www.${DOMAIN} -d app.${DOMAIN} -d api.${DOMAIN} -d docs.${DOMAIN} -d ${MAIL_DOMAIN} \
    --non-interactive --agree-tos --email ${ADMIN_EMAIL} --redirect

# Auto-renewal
systemctl enable certbot.timer
systemctl start certbot.timer

log_info "SSL certificates obtained"

# ============================================
# STEP 6: Configure Postfix Mail Server
# ============================================
log_step "6. Configuring Postfix..."

# Backup original config
cp /etc/postfix/main.cf /etc/postfix/main.cf.backup

cat > /etc/postfix/main.cf << EOF
# QuantumRishi Postfix Configuration
smtpd_banner = \$myhostname ESMTP
biff = no
append_dot_mydomain = no

# TLS parameters
smtpd_tls_cert_file=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
smtpd_tls_key_file=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
smtpd_tls_security_level = may
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_mandatory_ciphers = high
smtp_tls_security_level = may
smtp_tls_loglevel = 1

# General
myhostname = ${MAIL_DOMAIN}
mydomain = ${DOMAIN}
myorigin = \$mydomain
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
mynetworks = 127.0.0.0/8 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = all

# Maildir
home_mailbox = Maildir/

# SASL Authentication
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname
broken_sasl_auth_clients = yes

# Restrictions
smtpd_helo_required = yes
smtpd_helo_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname
smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_non_fqdn_sender, reject_unknown_sender_domain
smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination, reject_non_fqdn_recipient, reject_unknown_recipient_domain

# DKIM
milter_protocol = 6
milter_default_action = accept
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891

# Virtual mailbox
virtual_transport = lmtp:unix:private/dovecot-lmtp
EOF

cat > /etc/postfix/master.cf << 'EOF'
smtp      inet  n       -       y       -       -       smtpd
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlogd
EOF

log_info "Postfix configured"

# ============================================
# STEP 7: Configure Dovecot
# ============================================
log_step "7. Configuring Dovecot..."

cat > /etc/dovecot/dovecot.conf << EOF
protocols = imap pop3 lmtp
listen = *, ::
dict {
}
!include conf.d/*.conf
!include_try local.conf
EOF

cat > /etc/dovecot/conf.d/10-auth.conf << 'EOF'
disable_plaintext_auth = yes
auth_mechanisms = plain login
!include auth-system.conf.ext
EOF

cat > /etc/dovecot/conf.d/10-mail.conf << 'EOF'
mail_location = maildir:~/Maildir
namespace inbox {
  inbox = yes
}
EOF

cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = required
ssl_cert = </etc/letsencrypt/live/${DOMAIN}/fullchain.pem
ssl_key = </etc/letsencrypt/live/${DOMAIN}/privkey.pem
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes
EOF

cat > /etc/dovecot/conf.d/10-master.conf << 'EOF'
service imap-login {
  inet_listener imap {
    port = 0
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}
service pop3-login {
  inet_listener pop3 {
    port = 0
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = mail
  }
}
service auth-worker {
  user = mail
}
EOF

log_info "Dovecot configured"

# ============================================
# STEP 8: Configure OpenDKIM
# ============================================
log_step "8. Configuring OpenDKIM..."

mkdir -p /etc/opendkim/keys/${DOMAIN}

# Generate DKIM key if not exists
if [ ! -f /etc/opendkim/keys/${DOMAIN}/${DKIM_SELECTOR}.private ]; then
    opendkim-genkey -b 2048 -d ${DOMAIN} -D /etc/opendkim/keys/${DOMAIN} -s ${DKIM_SELECTOR} -v
fi

chown -R opendkim:opendkim /etc/opendkim/keys
chmod 700 /etc/opendkim/keys/${DOMAIN}
chmod 600 /etc/opendkim/keys/${DOMAIN}/${DKIM_SELECTOR}.private

cat > /etc/opendkim.conf << EOF
AutoRestart             Yes
AutoRestartRate         10/1h
Canonicalization        relaxed/simple
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                refile:/etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
LogWhy                  Yes
Mode                    sv
PidFile                 /run/opendkim/opendkim.pid
SignatureAlgorithm      rsa-sha256
Socket                  inet:8891@localhost
SyslogSuccess           Yes
TemporaryDirectory      /var/tmp
UMask                   002
UserID                  opendkim:opendkim
EOF

cat > /etc/opendkim/TrustedHosts << EOF
127.0.0.1
localhost
${DOMAIN}
*.${DOMAIN}
EOF

cat > /etc/opendkim/KeyTable << EOF
${DKIM_SELECTOR}._domainkey.${DOMAIN} ${DOMAIN}:${DKIM_SELECTOR}:/etc/opendkim/keys/${DOMAIN}/${DKIM_SELECTOR}.private
EOF

cat > /etc/opendkim/SigningTable << EOF
*@${DOMAIN} ${DKIM_SELECTOR}._domainkey.${DOMAIN}
EOF

mkdir -p /run/opendkim
chown opendkim:opendkim /run/opendkim

systemctl enable opendkim
systemctl restart opendkim
log_info "OpenDKIM configured"

# Print DKIM DNS record
log_info "DKIM DNS Record (add to Cloudflare if not already done):"
cat /etc/opendkim/keys/${DOMAIN}/${DKIM_SELECTOR}.txt

# ============================================
# STEP 9: Configure Docker
# ============================================
log_step "9. Configuring Docker..."

systemctl enable docker
systemctl start docker
usermod -aG docker ${RUNNER_USER} 2>/dev/null || true

log_info "Docker configured"

# ============================================
# STEP 10: Create GitHub Actions Runner User
# ============================================
log_step "10. Setting up GitHub Actions Runner..."

# Create runner user
if ! id "${RUNNER_USER}" &>/dev/null; then
    useradd -m -s /bin/bash ${RUNNER_USER}
fi

# Create runner directory
mkdir -p /opt/actions-runner
chown -R ${RUNNER_USER}:${RUNNER_USER} /opt/actions-runner

# Download runner (latest version)
cd /opt/actions-runner
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
if [ ! -f "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" ]; then
    curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
        https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
fi

chown -R ${RUNNER_USER}:${RUNNER_USER} /opt/actions-runner

log_info "GitHub Actions Runner downloaded"
log_warn "To configure the runner, run as ${RUNNER_USER}:"
echo "  sudo -u ${RUNNER_USER} /opt/actions-runner/config.sh --url https://github.com/QuantumRishi --token YOUR_RUNNER_TOKEN"
echo "  sudo /opt/actions-runner/svc.sh install ${RUNNER_USER}"
echo "  sudo /opt/actions-runner/svc.sh start"

# ============================================
# STEP 11: Create Mail User
# ============================================
log_step "11. Creating mail user..."

if ! id "mailuser" &>/dev/null; then
    useradd -m -s /bin/bash mailuser
    echo "mailuser:$(openssl rand -base64 32)" | chpasswd
    log_info "Mail user created (password saved to /root/mail-credentials.txt)"
fi

# ============================================
# STEP 12: Start Services
# ============================================
log_step "12. Starting all services..."

systemctl enable postfix dovecot opendkim nginx redis-server
systemctl restart postfix dovecot opendkim nginx redis-server

log_info "All services started"

# ============================================
# Final Summary
# ============================================
echo ""
echo "========================================"
echo -e "${GREEN}  SERVER PROVISIONING COMPLETE!${NC}"
echo "========================================"
echo ""
echo "Services Running:"
echo "  ✓ Nginx (web server)"
echo "  ✓ Postfix (SMTP)"
echo "  ✓ Dovecot (IMAP/POP3)"
echo "  ✓ OpenDKIM (email signing)"
echo "  ✓ Let's Encrypt (SSL)"
echo "  ✓ Docker"
echo "  ✓ Fail2Ban (security)"
echo ""
echo "Web URLs:"
echo "  https://${DOMAIN}"
echo "  https://app.${DOMAIN}"
echo "  https://api.${DOMAIN}"
echo "  https://docs.${DOMAIN}"
echo ""
echo "Mail Server:"
echo "  SMTP: ${MAIL_DOMAIN}:587 (STARTTLS)"
echo "  SMTPS: ${MAIL_DOMAIN}:465 (SSL)"
echo "  IMAP: ${MAIL_DOMAIN}:993 (SSL)"
echo ""
echo "Next Steps:"
echo "  1. Configure GitHub Runner with your token"
echo "  2. Deploy your applications"
echo "  3. Test email sending/receiving"
echo ""
echo "========================================"
