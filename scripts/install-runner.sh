#!/bin/bash
# GitHub Actions Runner Installation Script for QuantumRishi
# Run on each self-hosted runner server

set -euo pipefail

# Configuration
RUNNER_VERSION="2.321.0"
RUNNER_ARCH="linux-x64"
ORG="QuantumRishi"
RUNNER_USER="github-runner"
RUNNER_GROUP="github-runner"
RUNNER_HOME="/opt/actions-runner"
LABELS="self-hosted,linux,x64,qr"

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

# Check for required environment variable
if [[ -z "${QR_BOT_PAT:-}" ]]; then
    log_error "QR_BOT_PAT environment variable is required"
    echo "Export it before running: export QR_BOT_PAT='ghp_...'"
    exit 1
fi

log_info "Installing GitHub Actions Runner v${RUNNER_VERSION}"

# Create runner user
if ! id "${RUNNER_USER}" &>/dev/null; then
    log_info "Creating user ${RUNNER_USER}"
    useradd -r -m -d "${RUNNER_HOME}" -s /bin/bash "${RUNNER_USER}"
fi

# Create directory
mkdir -p "${RUNNER_HOME}"
cd "${RUNNER_HOME}"

# Download runner
log_info "Downloading runner package"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
curl -fsSL -o runner.tar.gz "${RUNNER_URL}"

# Verify checksum
log_info "Verifying checksum"
SHA256=$(curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz.sha256")
echo "${SHA256}  runner.tar.gz" | sha256sum -c -

# Extract
log_info "Extracting runner"
tar xzf runner.tar.gz
rm -f runner.tar.gz

# Get registration token from GitHub API
log_info "Getting registration token from GitHub API"
REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${QR_BOT_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/orgs/${ORG}/actions/runners/registration-token" \
    | jq -r '.token')

if [[ -z "${REG_TOKEN}" || "${REG_TOKEN}" == "null" ]]; then
    log_error "Failed to get registration token. Check your PAT permissions."
    exit 1
fi

# Generate unique runner name
RUNNER_NAME="qr-runner-$(hostname -s)-$(date +%s | tail -c 5)"
log_info "Configuring runner: ${RUNNER_NAME}"

# Set ownership
chown -R "${RUNNER_USER}:${RUNNER_GROUP}" "${RUNNER_HOME}"

# Configure runner as the runner user
su - "${RUNNER_USER}" -c "
    cd ${RUNNER_HOME}
    ./config.sh \
        --url 'https://github.com/${ORG}' \
        --token '${REG_TOKEN}' \
        --name '${RUNNER_NAME}' \
        --labels '${LABELS}' \
        --work '_work' \
        --unattended \
        --replace
"

# Install and start service
log_info "Installing systemd service"
./svc.sh install "${RUNNER_USER}"
./svc.sh start

# Verify service is running
sleep 2
if systemctl is-active --quiet "actions.runner.${ORG}.${RUNNER_NAME}.service"; then
    log_info "Runner '${RUNNER_NAME}' is now running!"
    log_info "Labels: ${LABELS}"
    log_info "View status: systemctl status actions.runner.${ORG}.${RUNNER_NAME}.service"
else
    log_error "Runner service failed to start"
    journalctl -u "actions.runner.${ORG}.${RUNNER_NAME}.service" -n 20
    exit 1
fi

# Create management script
cat > /usr/local/bin/qr-runner << 'SCRIPT'
#!/bin/bash
set -euo pipefail

RUNNER_HOME="/opt/actions-runner"
SERVICE_NAME=$(systemctl list-units --type=service | grep 'actions.runner' | awk '{print $1}')

case "${1:-}" in
    status)
        systemctl status "$SERVICE_NAME"
        ;;
    logs)
        journalctl -u "$SERVICE_NAME" -f
        ;;
    restart)
        sudo systemctl restart "$SERVICE_NAME"
        ;;
    stop)
        sudo systemctl stop "$SERVICE_NAME"
        ;;
    start)
        sudo systemctl start "$SERVICE_NAME"
        ;;
    update)
        echo "Updating runner..."
        sudo systemctl stop "$SERVICE_NAME"
        cd "$RUNNER_HOME"
        sudo -u github-runner ./bin/Runner.Listener --update
        sudo systemctl start "$SERVICE_NAME"
        ;;
    *)
        echo "Usage: qr-runner {status|logs|restart|stop|start|update}"
        exit 1
        ;;
esac
SCRIPT
chmod +x /usr/local/bin/qr-runner

log_info "Management script installed: qr-runner {status|logs|restart|stop|start|update}"
log_info "Runner installation complete!"
