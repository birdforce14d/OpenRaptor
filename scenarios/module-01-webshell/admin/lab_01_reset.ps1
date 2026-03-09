# =============================================================================
# Module 01 — Lab Reset (Admin)
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run on DC01 as Domain Admin to reset Module 01 for a new student.
# Rebuilds SP01 from golden image and re-seeds scenario prerequisites.
#
# What this script does:
#   1. Destroys current SP01 VM
#   2. Rebuilds SP01 from golden image (sp01-module01-student/1.0.0)
#   3. Waits for SP01 to boot and join domain
#   4. Re-runs lab_01_setup.ps1 to ensure accounts and tools are ready
#   5. Runs lab_01_check.ps1 to verify clean state
# =============================================================================

param(
    [string]$ResourceGroup = "rg-cirtlab-core",
    [string]$VMName = "win-norca-sp01",
    [string]$ImageId = "/subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/<YOUR_RESOURCE_GROUP>/providers/Microsoft.Compute/galleries/<YOUR_GALLERY_NAME>/images/sp01-module01-student/versions/1.0.0",
    [int]$TimeoutMinutes = 15
)

$ErrorActionPreference = "Stop"

Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  Module 01 — Lab Reset                       ║" -ForegroundColor Yellow
Write-Host "║  This will DESTROY and rebuild SP01           ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to reset Module 01? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

# --- Step 1: Delete SP01 ---
Write-Host "[1/5] Deleting SP01 VM..." -ForegroundColor Yellow
az vm delete --resource-group $ResourceGroup --name $VMName --yes --force-deletion true 2>$null
Write-Host "  [OK] VM deleted" -ForegroundColor Green

# Clean up disks and NICs
Write-Host "  Cleaning up orphaned resources..." -ForegroundColor Yellow
$disks = az disk list --resource-group $ResourceGroup --query "[?contains(name, 'sp01')].[name]" -o tsv
foreach ($d in $disks) {
    az disk delete --resource-group $ResourceGroup --name $d --yes 2>$null
}
$nics = az network nic list --resource-group $ResourceGroup --query "[?contains(name, 'sp01')].[name]" -o tsv
foreach ($n in $nics) {
    az network nic delete --resource-group $ResourceGroup --name $n 2>$null
}
Write-Host "  [OK] Cleanup done" -ForegroundColor Green

# --- Step 2: Rebuild from golden image ---
Write-Host "[2/5] Rebuilding SP01 from golden image..." -ForegroundColor Yellow
az vm create `
    --resource-group $ResourceGroup `
    --name $VMName `
    --image $ImageId `
    --size Standard_D4s_v3 `
    --vnet-name vnet-cirtlab `
    --subnet snet-target `
    --private-ip-address 10.10.2.10 `
    --public-ip-address "" `
    --admin-username cirtadmin `
    --admin-password "<YOUR_ADMIN_PASSWORD>" `
    --nsg "" `
    --no-wait

Write-Host "  [OK] VM creation initiated" -ForegroundColor Green

# --- Step 3: Wait for SP01 to boot ---
Write-Host "[3/5] Waiting for SP01 to come online (up to $TimeoutMinutes min)..." -ForegroundColor Yellow
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$ready = $false

while ((Get-Date) -lt $deadline) {
    $status = az vm get-instance-view --resource-group $ResourceGroup --name $VMName `
        --query "instanceView.statuses[1].displayStatus" -o tsv 2>$null
    if ($status -eq "VM running") {
        # Wait for IIS
        Start-Sleep -Seconds 30
        try {
            $r = Invoke-WebRequest -Uri "http://sharepoint.norca.click" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
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
    Write-Host "  [FAIL] SP01 did not come online within $TimeoutMinutes minutes" -ForegroundColor Red
    Write-Host "         Check Azure Portal for VM status" -ForegroundColor Red
    exit 1
}

# --- Step 4: Re-run setup ---
Write-Host "[4/5] Re-running lab setup..." -ForegroundColor Yellow
$setupScript = Join-Path $PSScriptRoot "lab_01_setup.ps1"
if (Test-Path $setupScript) {
    & $setupScript
} else {
    Write-Host "  [WARN] lab_01_setup.ps1 not found — seed accounts manually" -ForegroundColor Yellow
}

# --- Step 5: Verify ---
Write-Host "[5/5] Running final check..." -ForegroundColor Yellow
$checkScript = Join-Path $PSScriptRoot "lab_01_check.ps1"
if (Test-Path $checkScript) {
    & $checkScript
} else {
    Write-Host "  [WARN] lab_01_check.ps1 not found — verify manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Reset complete. Lab is ready for a new student." -ForegroundColor Cyan
