#!/bin/bash
# Automated Secrets Setup for QuantumRishi
# This script creates all required GitHub secrets using the GitHub CLI
# Run: ./setup-secrets.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
ORG="QuantumRishi"
REPOS=("qr.dev" "qr-db" "qr-mail" "qr-pipeline")

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed"
        echo "Install it from: https://cli.github.com/"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated with GitHub CLI"
        echo "Run: gh auth login"
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

# Generate secure random secrets
generate_secret() {
    openssl rand -base64 32 | tr -d '\n'
}

generate_hex_secret() {
    openssl rand -hex 32
}

# Create organization secrets
setup_org_secrets() {
    log_step "Setting up organization secrets for ${ORG}..."
    
    # Check if secrets already exist
    existing=$(gh secret list --org "$ORG" 2>/dev/null || echo "")
    
    # QR_BOT_PAT - Must be provided manually
    if ! echo "$existing" | grep -q "QR_BOT_PAT"; then
        log_warn "QR_BOT_PAT must be created manually with a fine-grained PAT"
        echo "  1. Go to: https://github.com/settings/tokens?type=beta"
        echo "  2. Generate new token with these permissions:"
        echo "     - Repository: Actions (Read/Write), Contents (Read/Write)"
        echo "     - Organization: Members (Read), Self-hosted runners (Read/Write)"
        echo "  3. Run: gh secret set QR_BOT_PAT --org $ORG"
        read -p "Press Enter after creating QR_BOT_PAT..."
    else
        log_info "QR_BOT_PAT already exists"
    fi
    
    # Cloudflare secrets - Must be provided
    if ! echo "$existing" | grep -q "CLOUDFLARE_API_TOKEN"; then
        log_warn "CLOUDFLARE_API_TOKEN required"
        echo "  1. Go to: https://dash.cloudflare.com/profile/api-tokens"
        echo "  2. Create token with Zone:Edit, Workers:Edit permissions"
        echo "  3. Run: gh secret set CLOUDFLARE_API_TOKEN --org $ORG"
        read -p "Press Enter after creating CLOUDFLARE_API_TOKEN..."
    else
        log_info "CLOUDFLARE_API_TOKEN already exists"
    fi
    
    if ! echo "$existing" | grep -q "CLOUDFLARE_ACCOUNT_ID"; then
        log_warn "CLOUDFLARE_ACCOUNT_ID required"
        echo "  Find it in Cloudflare Dashboard → Overview → Account ID"
        read -p "Enter CLOUDFLARE_ACCOUNT_ID: " cf_account_id
        if [[ -n "$cf_account_id" ]]; then
            echo "$cf_account_id" | gh secret set CLOUDFLARE_ACCOUNT_ID --org "$ORG"
            log_info "CLOUDFLARE_ACCOUNT_ID set"
        fi
    else
        log_info "CLOUDFLARE_ACCOUNT_ID already exists"
    fi
    
    # Optional notification webhooks
    read -p "Do you have a Slack webhook URL? (y/N): " has_slack
    if [[ "$has_slack" =~ ^[Yy]$ ]]; then
        read -p "Enter SLACK_WEBHOOK_URL: " slack_url
        if [[ -n "$slack_url" ]]; then
            echo "$slack_url" | gh secret set SLACK_WEBHOOK_URL --org "$ORG"
            log_info "SLACK_WEBHOOK_URL set"
        fi
    fi
    
    read -p "Do you have a Discord webhook URL? (y/N): " has_discord
    if [[ "$has_discord" =~ ^[Yy]$ ]]; then
        read -p "Enter DISCORD_WEBHOOK_URL: " discord_url
        if [[ -n "$discord_url" ]]; then
            echo "$discord_url" | gh secret set DISCORD_WEBHOOK_URL --org "$ORG"
            log_info "DISCORD_WEBHOOK_URL set"
        fi
    fi
}

# Create repository-specific secrets
setup_repo_secrets() {
    local repo=$1
    log_step "Setting up secrets for ${ORG}/${repo}..."
    
    existing=$(gh secret list --repo "${ORG}/${repo}" 2>/dev/null || echo "")
    
    case "$repo" in
        "qr.dev")
            # Generate JWT secret if not exists
            if ! echo "$existing" | grep -q "JWT_SECRET"; then
                jwt_secret=$(generate_secret)
                echo "$jwt_secret" | gh secret set JWT_SECRET --repo "${ORG}/${repo}"
                log_info "JWT_SECRET generated and set"
            fi
            
            # Supabase secrets - prompt user
            if ! echo "$existing" | grep -q "SUPABASE_URL"; then
                log_warn "Supabase credentials required for qr.dev"
                read -p "Enter SUPABASE_URL (or press Enter to skip): " supabase_url
                if [[ -n "$supabase_url" ]]; then
                    echo "$supabase_url" | gh secret set SUPABASE_URL --repo "${ORG}/${repo}"
                    log_info "SUPABASE_URL set"
                fi
            fi
            
            if ! echo "$existing" | grep -q "SUPABASE_ANON_KEY"; then
                read -p "Enter SUPABASE_ANON_KEY (or press Enter to skip): " supabase_anon
                if [[ -n "$supabase_anon" ]]; then
                    echo "$supabase_anon" | gh secret set SUPABASE_ANON_KEY --repo "${ORG}/${repo}"
                    log_info "SUPABASE_ANON_KEY set"
                fi
            fi
            
            if ! echo "$existing" | grep -q "SUPABASE_SERVICE_KEY"; then
                read -p "Enter SUPABASE_SERVICE_KEY (or press Enter to skip): " supabase_service
                if [[ -n "$supabase_service" ]]; then
                    echo "$supabase_service" | gh secret set SUPABASE_SERVICE_KEY --repo "${ORG}/${repo}"
                    log_info "SUPABASE_SERVICE_KEY set"
                fi
            fi
            ;;
            
        "qr-db")
            # Generate database secrets
            if ! echo "$existing" | grep -q "POSTGRES_PASSWORD"; then
                pg_password=$(generate_secret)
                echo "$pg_password" | gh secret set POSTGRES_PASSWORD --repo "${ORG}/${repo}"
                log_info "POSTGRES_PASSWORD generated and set"
                echo -e "${YELLOW}SAVE THIS:${NC} POSTGRES_PASSWORD = $pg_password"
            fi
            
            if ! echo "$existing" | grep -q "JWT_SECRET"; then
                jwt_secret=$(generate_secret)
                echo "$jwt_secret" | gh secret set JWT_SECRET --repo "${ORG}/${repo}"
                log_info "JWT_SECRET generated and set"
            fi
            ;;
            
        "qr-mail")
            # SMTP credentials
            if ! echo "$existing" | grep -q "SMTP_PASSWORD"; then
                smtp_password=$(generate_secret)
                echo "$smtp_password" | gh secret set SMTP_PASSWORD --repo "${ORG}/${repo}"
                log_info "SMTP_PASSWORD generated and set"
                echo -e "${YELLOW}SAVE THIS:${NC} SMTP_PASSWORD = $smtp_password"
            fi
            
            # Resend API key (optional)
            if ! echo "$existing" | grep -q "RESEND_API_KEY"; then
                read -p "Enter RESEND_API_KEY (or press Enter to skip): " resend_key
                if [[ -n "$resend_key" ]]; then
                    echo "$resend_key" | gh secret set RESEND_API_KEY --repo "${ORG}/${repo}"
                    log_info "RESEND_API_KEY set"
                fi
            fi
            ;;
            
        "qr-pipeline")
            # Runner token will be generated dynamically
            log_info "qr-pipeline uses dynamic runner tokens"
            ;;
    esac
}

# Create GitHub environments
setup_environments() {
    log_step "Setting up deployment environments..."
    
    for repo in "${REPOS[@]}"; do
        log_info "Creating environments for ${repo}..."
        
        # Create staging environment
        gh api --method PUT "/repos/${ORG}/${repo}/environments/staging" \
            --field "wait_timer=0" \
            --field "reviewers=[]" 2>/dev/null || true
        
        # Create production environment with protection
        gh api --method PUT "/repos/${ORG}/${repo}/environments/production" \
            --field "wait_timer=0" \
            --field "deployment_branch_policy={\"protected_branches\":true,\"custom_branch_policies\":false}" 2>/dev/null || true
    done
    
    log_info "Environments created"
}

# Main execution
main() {
    echo "========================================"
    echo "  QuantumRishi Secrets Setup"
    echo "========================================"
    echo ""
    
    check_prerequisites
    
    # Organization secrets
    setup_org_secrets
    
    # Repository secrets
    for repo in "${REPOS[@]}"; do
        setup_repo_secrets "$repo"
    done
    
    # Environments
    read -p "Set up deployment environments? (Y/n): " setup_envs
    if [[ ! "$setup_envs" =~ ^[Nn]$ ]]; then
        setup_environments
    fi
    
    echo ""
    echo "========================================"
    log_info "Secrets setup complete!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "  1. Verify secrets: gh secret list --org $ORG"
    echo "  2. Run test workflow to verify"
    echo "  3. Deploy your first application"
}

main "$@"
