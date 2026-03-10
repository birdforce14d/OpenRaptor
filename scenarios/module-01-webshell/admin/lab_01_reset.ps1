# =============================================================================
# Module 01 — Lab Reset (Admin)
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run on DC01 as Domain Admin to reset Module 01 for a new student.
# Rebuilds SP01 from golden image and re-seeds scenario prerequisites.
#
# What this script does:
#   1. Destroys current SP01 VM + orphaned disks/NICs
#   2. Rebuilds SP01 from golden image (Community Gallery)
#   3. Waits for SP01 to boot and join domain automatically (post-deploy extension)
#   4. Re-runs lab_01_setup.ps1 to ensure accounts and tools are ready
#   5. Runs lab_01_check.ps1 to verify clean state
#
# Requirements: az CLI authenticated with Contributor on rg-cirtlab-core
# =============================================================================

param(
    [string]$ResourceGroup   = "rg-cirtlab-core",
    [string]$VMName          = "win-norca-sp01",
    [string]$VNetName        = "vnet-cirtlab-base",
    [string]$SubnetName      = "snet-target-module01",
    [string]$PrivateIP       = "10.10.3.10",
    [string]$VMSize          = "Standard_D4s_v3",
    [string]$AdminUsername   = "cirtadmin",
    [string]$ImageId         = "/CommunityGalleries/cirtraptorlab-732fa912-74d1-4049-831b-83781b188c49/Images/sp01-module01/Versions/1.0.0",
    [int]$TimeoutMinutes     = 20
)

$ErrorActionPreference = "Stop"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Module 01 — Lab Reset                        ║" -ForegroundColor Yellow
Write-Host "║  This will DESTROY and rebuild SP01           ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to reset Module 01? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

# Admin password from environment — do NOT hardcode
$AdminPassword = $env:CIRT_ADMIN_PASSWORD
if (-not $AdminPassword) {
    $SecurePass = Read-Host "Enter cirtadmin password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
    $AdminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# --- Step 1: Delete SP01 ---
Write-Host "[1/5] Deleting SP01 VM ($VMName)..." -ForegroundColor Yellow
az vm delete --resource-group $ResourceGroup --name $VMName --yes --force-deletion true 2>$null
Write-Host "  [OK] VM deleted" -ForegroundColor Green

# Clean up orphaned disks and NICs
Write-Host "  Cleaning up orphaned resources..." -ForegroundColor Yellow
$disks = az disk list --resource-group $ResourceGroup --query "[?contains(name, 'sp01')].[name]" -o tsv 2>$null
foreach ($d in ($disks -split "`n" | Where-Object { $_ })) {
    az disk delete --resource-group $ResourceGroup --name $d --yes 2>$null
    Write-Host "  [OK] Deleted disk: $d" -ForegroundColor Green
}
$nics = az network nic list --resource-group $ResourceGroup --query "[?contains(name, 'sp01')].[name]" -o tsv 2>$null
foreach ($n in ($nics -split "`n" | Where-Object { $_ })) {
    az network nic delete --resource-group $ResourceGroup --name $n 2>$null
    Write-Host "  [OK] Deleted NIC: $n" -ForegroundColor Green
}
Write-Host "  [OK] Cleanup done" -ForegroundColor Green

# --- Step 2: Get subnet ID ---
Write-Host "[2/5] Looking up subnet ID..." -ForegroundColor Yellow
$SubnetId = az network vnet subnet show `
    --resource-group "rg-cirtlab-network" `
    --vnet-name $VNetName `
    --name $SubnetName `
    --query id -o tsv 2>$null

if (-not $SubnetId) {
    Write-Host "  [FAIL] Could not find subnet $SubnetName in $VNetName" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Subnet: $SubnetId" -ForegroundColor Green

# --- Step 3: Rebuild from golden image ---
Write-Host "[3/5] Rebuilding SP01 from golden image..." -ForegroundColor Yellow
az vm create `
    --resource-group $ResourceGroup `
    --name $VMName `
    --image $ImageId `
    --size $VMSize `
    --subnet $SubnetId `
    --private-ip-address $PrivateIP `
    --public-ip-address '""' `
    --admin-username $AdminUsername `
    --admin-password $AdminPassword `
    --nsg '""' `
    --no-wait

Write-Host "  [OK] VM creation initiated" -ForegroundColor Green

# --- Step 4: Wait for SP01 to come online ---
Write-Host "[4/5] Waiting for SP01 to come online (up to $TimeoutMinutes min)..." -ForegroundColor Yellow
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$ready = $false

while ((Get-Date) -lt $deadline) {
    $status = az vm get-instance-view --resource-group $ResourceGroup --name $VMName `
        --query "instanceView.statuses[1].displayStatus" -o tsv 2>$null
    if ($status -eq "VM running") {
        Start-Sleep -Seconds 60  # give IIS time to start after post-deploy extension
        try {
            $r = Invoke-WebRequest -Uri "http://sharepoint.norca.click" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $ready = $true
            break
        } catch {
            if ($_.Exception.Response) { $ready = $true; break }  # 401 = IIS up
        }
    }
    Write-Host "  Waiting... ($status)" -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}

if ($ready) {
    Write-Host "  [OK] SP01 is online and IIS is responding" -ForegroundColor Green
} else {
    Write-Host "  [WARN] SP01 did not respond within $TimeoutMinutes minutes" -ForegroundColor Yellow
    Write-Host "         Check Azure Portal — post-deploy extension may still be running" -ForegroundColor Yellow
    Write-Host "         Check C:\Windows\Temp\post-deploy.log on SP01 via Bastion" -ForegroundColor Yellow
}

# --- Step 5: Re-run setup + verify ---
Write-Host "[5/5] Re-running lab setup and check..." -ForegroundColor Yellow
$setupScript = Join-Path $PSScriptRoot "lab_01_setup.ps1"
if (Test-Path $setupScript) {
    & $setupScript
} else {
    Write-Host "  [WARN] lab_01_setup.ps1 not found at $PSScriptRoot — seed accounts manually" -ForegroundColor Yellow
}

$checkScript = Join-Path $PSScriptRoot "lab_01_check.ps1"
if (Test-Path $checkScript) {
    & $checkScript
} else {
    Write-Host "  [WARN] lab_01_check.ps1 not found — verify manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Reset complete. Lab is ready for a new student." -ForegroundColor Cyan
