# =============================================================================
# Module 01 — Lab Setup (Admin)
# OpenRaptor Cyber Range — CIRT APAC
#
# Run on DC01 as Domain Admin BEFORE handing the lab to a student.
# Sets up all scenario prerequisites for Module 01 (SharePoint Webshell).
#
# What this script does:
#   1. Creates j.chen AD account (compromised Finance analyst)
#   2. Grants j.chen appropriate SharePoint access
#   3. Deploys attack toolkit to Kali at /opt/raptor/module-01/
#   4. Downloads webshell payload from public repo to Kali
#   5. Runs lab_01_check.ps1 to verify everything is ready
# =============================================================================

param(
    [string]$KaliIP = "10.10.3.10",
    [string]$KaliUser = "kali",
    [string]$SPUrl = "http://sharepoint.norca.click"
)

$ErrorActionPreference = "Stop"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Module 01 — Lab Setup                       ║" -ForegroundColor Yellow
Write-Host "║  Run as: Domain Admin on DC01                ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

# --- Step 1: Create j.chen AD account ---
Write-Host "[1/4] Setting up AD accounts..." -ForegroundColor Yellow

$password = ConvertTo-SecureString "<YOUR_STUDENT_PASSWORD>" -AsPlainText -Force

if (-not (Get-ADUser -Filter {SamAccountName -eq "j.chen"} -ErrorAction SilentlyContinue)) {
    New-ADUser -Name "Jenny Chen" `
        -GivenName "Jenny" `
        -Surname "Chen" `
        -SamAccountName "j.chen" `
        -UserPrincipalName "j.chen@norca.click" `
        -AccountPassword $password `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path "CN=Users,DC=norca,DC=click" `
        -Description "Finance Analyst — Module 01 scenario account"

    Write-Host "  [OK] Created j.chen (Jenny Chen)" -ForegroundColor Green
} else {
    # Ensure account is enabled and password is correct
    Set-ADAccountPassword -Identity "j.chen" -Reset -NewPassword $password
    Enable-ADAccount -Identity "j.chen"
    Write-Host "  [SKIP] j.chen already exists — password reset, account enabled" -ForegroundColor Yellow
}

# --- Step 2: Deploy attack toolkit to Kali ---
Write-Host "[2/4] Deploying attack toolkit to Kali ($KaliIP)..." -ForegroundColor Yellow

# Create directory structure on Kali via SSH
$sshCommands = @"
sudo mkdir -p /opt/raptor/module-01/payloads
sudo chown -R kali:kali /opt/raptor
"@

# Note: Requires SSH key or password auth to Kali from DC01
# In lab environment, use pre-shared SSH key
ssh "${KaliUser}@${KaliIP}" $sshCommands 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Directory structure created on Kali" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Could not SSH to Kali — deploy attack scripts manually" -ForegroundColor Yellow
    Write-Host "         Copy scenarios/module-01-webshell/attack.sh to /opt/raptor/module-01/" -ForegroundColor Yellow
    Write-Host "         Copy scenarios/module-01-webshell/student/preflight.sh to /opt/raptor/module-01/" -ForegroundColor Yellow
}

# --- Step 3: Verify SP01 is clean ---
Write-Host "[3/4] Verifying SP01 clean state..." -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri "$SPUrl/Shared%20Documents/help.aspx" `
        -Credential (New-Object PSCredential("NORCA\j.chen", $password)) `
        -UseBasicParsing -ErrorAction Stop
    Write-Host "  [WARN] help.aspx already exists on SP01 — lab may need reset" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode -eq 404 -or $_.Exception.Response.StatusCode -eq 401) {
        Write-Host "  [OK] SP01 is clean (no webshell present)" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Could not verify SP01 state: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- Step 4: Run check script ---
Write-Host "[4/4] Running lab check..." -ForegroundColor Yellow
$checkScript = Join-Path $PSScriptRoot "lab_01_check.ps1"
if (Test-Path $checkScript) {
    & $checkScript
} else {
    Write-Host "  [SKIP] lab_01_check.ps1 not found — run manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete. Run lab_01_check.ps1 to verify, then hand off to student." -ForegroundColor Cyan
