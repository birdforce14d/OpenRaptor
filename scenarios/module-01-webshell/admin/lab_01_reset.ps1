# =============================================================================
# Module 01 — Lab Reset (Admin)
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run on DC01 as Domain Admin to reset Module 01 for a new student.
# Rebuilds SP01 from the clean golden image and re-runs setup.
# Reset time: ~10 minutes.
# =============================================================================
param(
    [string]$ResourceGroup = "rg-cirtlab-core",
    [string]$AttackerRG    = "rg-cirtlab-attacker",
    [string]$VMName        = "win-norca-sp01",
    [string]$Location      = "australiaeast",
    # Community Gallery path — no subscription/tenant dependency
    [string]$ImageId       = "/CommunityGalleries/cirtraptorlab-732fa912-74d1-4049-831b-83781b188c49/Images/sp01-module01-student/Versions/1.0.0",
    [string]$VMSize        = "Standard_D2s_v3",
    [string]$AdminUser     = "cirtadmin",
    [string]$SubnetId      = "",  # auto-detected if blank
    [int]$TimeoutMinutes   = 15
)

$ErrorActionPreference = "Stop"
$AdminPass = "CirtApacAdm!n2026"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Module 01 — Lab Reset                       ║" -ForegroundColor Yellow
Write-Host "║  Rebuilds SP01 from clean golden image       ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Image: sp01-module01-student (noWS — clean)" -ForegroundColor Cyan
Write-Host "  VM:    $VMName in $ResourceGroup" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Confirm reset? All student data on SP01 will be lost. (yes/no)"
if ($confirm -ne "yes") { Write-Host "Aborted." -ForegroundColor Yellow; exit 0 }

# ── Step 1: Delete SP01 ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/5] Deleting SP01..." -ForegroundColor Yellow
az vm delete --resource-group $ResourceGroup --name $VMName --yes --force-deletion true 2>&1 | Out-Null
# Also clean up NIC and OS disk left behind
az network nic delete --resource-group $ResourceGroup --name "${VMName}-nic" 2>&1 | Out-Null
az disk delete --resource-group $ResourceGroup --name "${VMName}-osdisk" --yes 2>&1 | Out-Null
Write-Host "  [OK] SP01 deleted" -ForegroundColor Green

# ── Step 2: Get subnet ID ─────────────────────────────────────────────────────
if (-not $SubnetId) {
    Write-Host ""
    Write-Host "[2/5] Resolving subnet..." -ForegroundColor Yellow
    $SubnetId = az network vnet subnet show `
        --resource-group "rg-cirtlab-network" `
        --vnet-name (az network vnet list -g "rg-cirtlab-network" --query "[0].name" -o tsv) `
        --name "snet-target-module01" --query id -o tsv 2>&1
    Write-Host "  [OK] Subnet: $SubnetId" -ForegroundColor Green
} else {
    Write-Host "[2/5] Using provided subnet ID" -ForegroundColor Yellow
}

# ── Step 3: Create NIC ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/5] Creating NIC..." -ForegroundColor Yellow
az network nic create `
    --resource-group $ResourceGroup `
    --name "${VMName}-nic" `
    --subnet $SubnetId `
    --private-ip-address "10.10.3.10" `
    --location $Location 2>&1 | Out-Null
Write-Host "  [OK] NIC created (10.10.3.10)" -ForegroundColor Green

# ── Step 4: Create VM from Community Gallery image ────────────────────────────
Write-Host ""
Write-Host "[4/5] Deploying SP01 from golden image..." -ForegroundColor Yellow
Write-Host "  This takes 5-8 minutes..." -ForegroundColor Gray

az vm create `
    --resource-group $ResourceGroup `
    --name $VMName `
    --image $ImageId `
    --size $VMSize `
    --admin-username $AdminUser `
    --admin-password $AdminPass `
    --nics "${VMName}-nic" `
    --os-disk-name "${VMName}-osdisk" `
    --storage-sku Premium_LRS `
    --location $Location `
    --no-wait 2>&1 | Out-Null

# Wait for VM to be running
$waited = 0
do {
    Start-Sleep 30
    $waited += 0.5
    $state = az vm get-instance-view -g $ResourceGroup -n $VMName `
        --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" `
        -o tsv 2>$null
    Write-Host "  Waiting... ($waited min) — $state" -ForegroundColor Gray
} while ($state -notlike "*running*" -and $waited -lt $TimeoutMinutes)

if ($state -like "*running*") {
    Write-Host "  [OK] SP01 running" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] SP01 did not reach running state within $TimeoutMinutes min" -ForegroundColor Red
    exit 1
}

# ── Step 5: Re-run setup and verify ───────────────────────────────────────────
Write-Host ""
Write-Host "[5/5] Running lab setup and verification..." -ForegroundColor Yellow
$setupScript = Join-Path $PSScriptRoot "lab_01_setup.ps1"
if (Test-Path $setupScript) {
    & $setupScript
} else {
    Write-Host "  [WARN] lab_01_setup.ps1 not found at $setupScript — run manually" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Reset complete. SP01 is clean and ready.    ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
