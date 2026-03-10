# =============================================================================
# Module 01 — Lab Check (Admin)
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run on DC01 as Domain Admin to verify the lab is ready for a student.
# This checks every prerequisite for Module 01.
# =============================================================================

param(
    [string]$KaliIP = "10.10.2.10",
    [string]$DCIP = "10.10.1.10",
    [string]$SPIP = "10.10.3.10",
    [string]$SPUrl = "http://sharepoint.norca.click"
)

$ErrorActionPreference = "SilentlyContinue"
$pass = 0; $fail = 0

function Check($desc, $ok, $failMsg) {
    if ($ok) {
        Write-Host "  [OK] $desc" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $desc" -ForegroundColor Red
        if ($failMsg) { Write-Host "         -> $failMsg" -ForegroundColor Red }
        $script:fail++
    }
}

Write-Host ""
Write-Host "Module 01 — Admin Lab Check" -ForegroundColor Yellow
Write-Host "===========================" -ForegroundColor Yellow
Write-Host ""

# --- 1. DC01 ---
Write-Host "[1/5] Domain Controller (DC01)" -ForegroundColor Yellow
Check "DC01 reachable" (Test-Connection $DCIP -Count 1 -Quiet)
Check "AD DS service running" ((Get-Service NTDS -ErrorAction SilentlyContinue).Status -eq 'Running') "AD DS not running"
Check "DNS service running" ((Get-Service DNS -ErrorAction SilentlyContinue).Status -eq 'Running') "DNS not running"
Write-Host ""

# --- 2. SP01 ---
Write-Host "[2/5] SharePoint Server (SP01)" -ForegroundColor Yellow
Check "SP01 reachable" (Test-Connection $SPIP -Count 1 -Quiet)

$iisOk = $false
try {
    $r = Invoke-WebRequest -Uri $SPUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $iisOk = ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
} catch {
    if ($_.Exception.Response) { $iisOk = $true }  # 401 = IIS is responding
}
Check "IIS responding on SP01" $iisOk "IIS may not be running — check post-deploy log at C:\Windows\Temp\post-deploy.log"

# Domain join check via DNS
$spDns = Resolve-DnsName "win-norca-sp01.norca.click" -Server $DCIP -ErrorAction SilentlyContinue
Check "SP01 domain-joined (DNS A record)" ($null -ne $spDns) "SP01 not found in AD DNS — may not be domain-joined"
Write-Host ""

# --- 3. AD Accounts ---
Write-Host "[3/5] Scenario Accounts" -ForegroundColor Yellow
$jchen = Get-ADUser -Filter {SamAccountName -eq "j.chen"} -ErrorAction SilentlyContinue
Check "j.chen account exists" ($null -ne $jchen) "Run lab_01_setup.ps1 to create"

if ($jchen) {
    Check "j.chen is enabled" ($jchen.Enabled) "Run: Enable-ADAccount j.chen"
}

$student = Get-ADUser -Filter {SamAccountName -eq "cirtstudent"} -ErrorAction SilentlyContinue
Check "cirtstudent account exists" ($null -ne $student) "Run lab_01_setup.ps1 to create"
Write-Host ""

# --- 4. Clean state ---
Write-Host "[4/5] Clean State" -ForegroundColor Yellow
$shellExists = $false
try {
    $password = ConvertTo-SecureString "CirtApacStudent2026" -AsPlainText -Force
    $cred = New-Object PSCredential("NORCA\j.chen", $password)
    $r = Invoke-WebRequest -Uri "$SPUrl/Shared%20Documents/help.aspx" -Credential $cred -UseBasicParsing -ErrorAction Stop
    $shellExists = $true
} catch {
    # 404 or 401 = clean
}
Check "SP01 is clean (no webshell)" (-not $shellExists) "help.aspx already exists — run lab_01_reset.ps1"
Write-Host ""

# --- 5. Kali ---
Write-Host "[5/5] Kali Attack Machine" -ForegroundColor Yellow
Check "Kali reachable" (Test-Connection $KaliIP -Count 1 -Quiet) "Kali01 unreachable at $KaliIP"

$toolsOk = $false
try {
    $result = ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "kali@$KaliIP" `
        "test -x /opt/raptor/module-01/attack.sh && test -f /opt/raptor/module-01/payloads/help.aspx && echo OK" 2>$null
    $toolsOk = ($result -eq "OK")
} catch {}
Check "Attack toolkit deployed on Kali" $toolsOk "Run kali_01_setup.sh on Kali01 to stage the toolkit"
Write-Host ""

# --- Summary ---
Write-Host "===========================" -ForegroundColor Yellow
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  ALL $total CHECKS PASSED" -ForegroundColor Green
    Write-Host "  Lab is ready. Hand off to student." -ForegroundColor Green
} else {
    Write-Host "  $fail/$total CHECKS FAILED" -ForegroundColor Red
    Write-Host "  Fix issues above before handing to student." -ForegroundColor Red
}
Write-Host ""
