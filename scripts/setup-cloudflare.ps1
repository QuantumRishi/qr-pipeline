# Cloudflare DNS Setup Script using API (PowerShell)
# Creates all required DNS records for quantum-rishi.com

param(
    [Parameter(Mandatory=$true)]
    [string]$AppIP,

    [Parameter(Mandatory=$false)]
    [string]$ApiIP = $AppIP,

    [Parameter(Mandatory=$true)]
    [string]$MailIP,

    [Parameter(Mandatory=$false)]
    [string]$DbIP = $AppIP
)

# Configuration
$DOMAIN = "quantum-rishi.com"
$CLOUDFLARE_API_TOKEN = $env:CLOUDFLARE_API_TOKEN
$CLOUDFLARE_ACCOUNT_ID = $env:CLOUDFLARE_ACCOUNT_ID

# Colors for output
$Green = "Green"
$Yellow = "Yellow"
$Red = "Red"
$Cyan = "Cyan"

function Write-LogInfo { param($Message) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] INFO: $Message" -ForegroundColor $Green }
function Write-LogWarn { param($Message) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] WARN: $Message" -ForegroundColor $Yellow }
function Write-LogError { param($Message) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] ERROR: $Message" -ForegroundColor $Red }
function Write-LogStep { param($Message) Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] STEP: $Message" -ForegroundColor $Cyan }

# Check prerequisites
function Test-Prerequisites {
    $missing = 0

    if ([string]::IsNullOrEmpty($CLOUDFLARE_API_TOKEN)) {
        Write-LogError "CLOUDFLARE_API_TOKEN is not set"
        $missing++
    }

    if ([string]::IsNullOrEmpty($CLOUDFLARE_ACCOUNT_ID)) {
        Write-LogWarn "CLOUDFLARE_ACCOUNT_ID is not set"
        # Try to get it from secrets or prompt
        $script:CLOUDFLARE_ACCOUNT_ID = Read-Host "Enter CLOUDFLARE_ACCOUNT_ID"
    }

    if ($missing -gt 0) {
        Write-Host ""
        Write-Host "Set these environment variables:"
        Write-Host "  `$env:CLOUDFLARE_API_TOKEN='your-api-token'"
        Write-Host "  `$env:CLOUDFLARE_ACCOUNT_ID='your-account-id'"
        exit 1
    }
}

# Get zone ID from domain
function Get-ZoneId {
    try {
        $headers = @{
            "Authorization" = "Bearer $CLOUDFLARE_API_TOKEN"
            "Content-Type" = "application/json"
        }

        $response = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" -Headers $headers -Method GET
        return $response.result[0].id
    }
    catch {
        Write-LogError "Failed to get zone ID: $($_.Exception.Message)"
        return $null
    }
}

# Create or update DNS record
function Set-DnsRecord {
    param(
        [string]$Type,
        [string]$Name,
        [string]$Content,
        [bool]$Proxied = $false,
        [int]$Ttl = 3600
    )

    try {
        $zoneId = Get-ZoneId
        if ([string]::IsNullOrEmpty($zoneId)) {
            Write-LogError "Could not get zone ID"
            return
        }

        $headers = @{
            "Authorization" = "Bearer $CLOUDFLARE_API_TOKEN"
            "Content-Type" = "application/json"
        }

        # Check if record exists
        $existingRecords = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?type=$Type&name=$Name.$DOMAIN" -Headers $headers -Method GET

        $recordData = @{
            type = $Type
            name = $Name
            content = $Content
            proxied = $Proxied
            ttl = $Ttl
        }

        if ($existingRecords.result.Count -gt 0) {
            # Update existing record
            $recordId = $existingRecords.result[0].id
            $response = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records/$recordId" -Headers $headers -Method PUT -Body ($recordData | ConvertTo-Json)
            if ($response.success) {
                Write-LogInfo "Updated: $Name.$DOMAIN ($Type)"
            } else {
                Write-LogError "Failed to update $Name $($response.errors[0].message)"
            }
        } else {
            # Create new record
            $response = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records" -Headers $headers -Method POST -Body ($recordData | ConvertTo-Json)
            if ($response.success) {
                Write-LogInfo "Created: $Name.$DOMAIN ($Type)"
            } else {
                Write-LogError "Failed to create $Name $($response.errors[0].message)"
            }
        }
    }
    catch {
        Write-LogError "Failed to set DNS record: $($_.Exception.Message)"
    }
}

# Main setup
function Invoke-Main {
    Write-Host "========================================" -ForegroundColor $Cyan
    Write-Host "  Cloudflare DNS Setup for $DOMAIN" -ForegroundColor $Cyan
    Write-Host "========================================" -ForegroundColor $Cyan
    Write-Host ""

    Test-Prerequisites

    Write-LogStep "Creating A records..."

    # A Records (proxied through Cloudflare)
    Set-DnsRecord -Type "A" -Name "app" -Content $AppIP -Proxied $true -Ttl 1
    Set-DnsRecord -Type "A" -Name "api" -Content $ApiIP -Proxied $true -Ttl 1
    Set-DnsRecord -Type "A" -Name "docs" -Content $AppIP -Proxied $true -Ttl 1

    # Mail server (NOT proxied - mail needs direct connection)
    Set-DnsRecord -Type "A" -Name "mail" -Content $MailIP -Proxied $false -Ttl 3600

    # Database (NOT proxied for direct connection)
    Set-DnsRecord -Type "A" -Name "db" -Content $DbIP -Proxied $false -Ttl 3600

    Write-LogStep "Creating MX record..."

    # MX Record
    try {
        $zoneId = Get-ZoneId
        $headers = @{
            "Authorization" = "Bearer $CLOUDFLARE_API_TOKEN"
            "Content-Type" = "application/json"
        }

        $mxData = @{
            type = "MX"
            name = "@"
            content = "mail.$DOMAIN"
            priority = 10
            ttl = 3600
        }

        $response = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records" -Headers $headers -Method POST -Body ($mxData | ConvertTo-Json)
        if ($response.success) {
            Write-LogInfo "MX record configured"
        }
    }
    catch {
        Write-LogWarn "MX record may already exist or failed to create"
    }

    Write-LogStep "Creating email authentication records..."

    # SPF Record
    Set-DnsRecord -Type "TXT" -Name "@" -Content "v=spf1 mx a:mail.$DOMAIN include:_spf.google.com ~all"

    # DMARC Record
    Set-DnsRecord -Type "TXT" -Name "_dmarc" -Content "v=DMARC1; p=quarantine; rua=mailto:dmarc@$DOMAIN; ruf=mailto:dmarc@$DOMAIN; fo=1"

    # MTA-STS Record
    Set-DnsRecord -Type "TXT" -Name "_mta-sts" -Content "v=STSv1; id=$((Get-Date).ToString('yyyyMMddHHmmss'))"

    # TLSRPT Record
    Set-DnsRecord -Type "TXT" -Name "_smtp._tls" -Content "v=TLSRPTv1; rua=mailto:tls-reports@$DOMAIN"

    Write-LogStep "Configuring SSL/TLS settings..."

    try {
        $zoneId = Get-ZoneId
        $headers = @{
            "Authorization" = "Bearer $CLOUDFLARE_API_TOKEN"
            "Content-Type" = "application/json"
        }

        # Set SSL mode to Full (Strict)
        $sslData = @{ value = "strict" } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/settings/ssl" -Headers $headers -Method PATCH -Body $sslData | Out-Null
        Write-LogInfo "SSL mode set to Full (Strict)"

        # Enable Always Use HTTPS
        $httpsData = @{ value = "on" } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/settings/always_use_https" -Headers $headers -Method PATCH -Body $httpsData | Out-Null
        Write-LogInfo "Always Use HTTPS enabled"

        # Enable Automatic HTTPS Rewrites
        $rewriteData = @{ value = "on" } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/settings/automatic_https_rewrites" -Headers $headers -Method PATCH -Body $rewriteData | Out-Null
        Write-LogInfo "Automatic HTTPS Rewrites enabled"

        # Enable HSTS
        $hstsData = @{
            value = @{
                strict_transport_security = @{
                    enabled = $true
                    max_age = 31536000
                    include_subdomains = $true
                    preload = $true
                }
            }
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/settings/security_header" -Headers $headers -Method PATCH -Body $hstsData | Out-Null
        Write-LogInfo "HSTS enabled with preload"

        # Minimum TLS 1.2
        $tlsData = @{ value = "1.2" } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/settings/min_tls_version" -Headers $headers -Method PATCH -Body $tlsData | Out-Null
        Write-LogInfo "Minimum TLS version set to 1.2"

    }
    catch {
        Write-LogWarn "Some SSL settings may have failed: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor $Green
    Write-LogInfo "DNS and Security setup complete!"
    Write-Host "========================================" -ForegroundColor $Green
    Write-Host ""
    Write-Host "Records created:"
    Write-Host "  - app.$DOMAIN → $AppIP (proxied)"
    Write-Host "  - api.$DOMAIN → $ApiIP (proxied)"
    Write-Host "  - docs.$DOMAIN → $AppIP (proxied)"
    Write-Host "  - mail.$DOMAIN → $MailIP (direct)"
    Write-Host "  - db.$DOMAIN → $DbIP (direct)"
    Write-Host "  - MX → mail.$DOMAIN"
    Write-Host "  - SPF, DMARC, MTA-STS, TLSRPT records"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Generate DKIM keys: ./scripts/generate-dkim.sh"
    Write-Host "  2. Add DKIM TXT record from generated output"
    Write-Host "  3. Set up SSL certificates on mail server"
    Write-Host "  4. Configure and start mail services"
}

# Run main function
Invoke-Main