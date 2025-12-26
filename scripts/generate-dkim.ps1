# DKIM Key Generation Script for QuantumRishi Mail Server
# PowerShell version for Windows compatibility
# Generates DKIM keypair and outputs DNS record for Cloudflare

param(
    [string]$Domain = "quantum-rishi.com",
    [string]$Selector = "qr202501"
)

$KEY_DIR = ".\dkim-keys\$Domain"

# Colors for output
$RED = "Red"
$GREEN = "Green"
$YELLOW = "Yellow"
$BLUE = "Blue"

function Write-ColorOutput {
    param([string]$Color, [string]$Message)
    Write-Host $Message -ForegroundColor $Color
}

function Write-Info { param([string]$Message) Write-ColorOutput $GREEN "[INFO] $Message" }
function Write-Step { param([string]$Message) Write-ColorOutput $BLUE "[STEP] $Message" }

Write-Host "========================================" -ForegroundColor White
Write-Host "  DKIM Key Generation for $Domain" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host ""

# Create directory
if (!(Test-Path $KEY_DIR)) {
    New-Item -ItemType Directory -Path $KEY_DIR -Force | Out-Null
}

Write-Step "Generating 2048-bit DKIM keypair..."

# Generate private key
cmd /c "`"$opensslPath`" genrsa -out `"$privateKeyPath`" 2048" 2>$null
if ($LASTEXITCODE -ne 0) { Write-ColorOutput $RED "Failed to generate private key"; exit 1 }

# Generate public key
cmd /c "`"$opensslPath`" rsa -in `"$privateKeyPath`" -pubout -out `"$publicKeyPath`"" 2>$null
if ($LASTEXITCODE -ne 0) { Write-ColorOutput $RED "Failed to generate public key"; exit 1 }

# Extract public key for DNS (remove headers and join lines)
$publicKeyContent = Get-Content $publicKeyPath
$publicKeyLines = $publicKeyContent | Where-Object { $_ -notmatch "^-" }
$PUBLIC_KEY = $publicKeyLines -join ""

Write-Info "Keys generated successfully!"
Write-Host ""

Write-Host "========================================" -ForegroundColor $YELLOW
Write-Host "DNS RECORD TO ADD:" -ForegroundColor $YELLOW
Write-Host "========================================" -ForegroundColor White
Write-Host ""
Write-ColorOutput $GREEN "Record Type: TXT"
Write-ColorOutput $GREEN "Name: ${Selector}._domainkey"
Write-ColorOutput $GREEN "Content:"
Write-Host ""
Write-Host "v=DKIM1; k=rsa; p=$PUBLIC_KEY"
Write-Host ""

Write-Host "========================================" -ForegroundColor $YELLOW
Write-Host "CLOUDFLARE DASHBOARD INSTRUCTIONS:" -ForegroundColor $YELLOW
Write-Host "========================================" -ForegroundColor White
Write-Host ""
Write-Host "1. Go to: https://dash.cloudflare.com" -ForegroundColor Cyan
Write-Host "2. Select $Domain domain" -ForegroundColor Cyan
Write-Host "3. Go to DNS → Records" -ForegroundColor Cyan
Write-Host "4. Click 'Add record'" -ForegroundColor Cyan
Write-Host "5. Type: TXT" -ForegroundColor White
Write-Host "6. Name: ${Selector}._domainkey" -ForegroundColor White
Write-Host "7. Content: v=DKIM1; k=rsa; p=$PUBLIC_KEY" -ForegroundColor White
Write-Host "8. TTL: Auto (or 3600)" -ForegroundColor White
Write-Host "9. Click Save" -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor $GREEN
Write-Host "Key files saved to:" -ForegroundColor $GREEN
Write-Host "========================================" -ForegroundColor White
Write-Host "  Private key: $privateKeyPath" -ForegroundColor White
Write-Host "  Public key:  $publicKeyPath" -ForegroundColor White
Write-Host ""

# Create a summary file
$dnsRecordPath = "$KEY_DIR\dns-record.txt"
@"
DKIM DNS Record for $Domain
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
Selector: $Selector

Record Type: TXT
Name: ${Selector}._domainkey
Content: v=DKIM1; k=rsa; p=$PUBLIC_KEY

Full record name: ${Selector}._domainkey.$Domain
"@ | Out-File -FilePath $dnsRecordPath -Encoding UTF8

Write-Info "DNS record also saved to: $dnsRecordPath"

Write-Host ""
Write-Step "Next step: Add the DNS record above to Cloudflare, then run server setup"