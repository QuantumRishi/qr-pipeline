#!/bin/bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
# Reload mail services after certificate renewal

set -e

# Reload Postfix
if systemctl is-active --quiet postfix; then
    systemctl reload postfix
    logger -t certbot "Reloaded Postfix after certificate renewal"
fi

# Reload Dovecot
if systemctl is-active --quiet dovecot; then
    systemctl reload dovecot
    logger -t certbot "Reloaded Dovecot after certificate renewal"
fi

# Reload nginx if used
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    logger -t certbot "Reloaded Nginx after certificate renewal"
fi

# Send notification
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
    curl -s -X POST -H 'Content-type: application/json' \
        --data '{"text":":lock: SSL certificate renewed for '"${RENEWED_DOMAINS:-unknown}"'"}' \
        "$SLACK_WEBHOOK_URL"
fi

exit 0
