# =============================================================================
# Module 01 — Lab Check (Admin)
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run on DC01 as Domain Admin to verify the lab is ready for a student.
# All checks must pass before handing off.
# =============================================================================
param(
    [string]$DCIP   = "10.10.1.10",
    [string]$SPIP   = "10.10.3.10",
    [string]$KaliIP = "10.10.2.10",
    [string]$SPUrl  = "http://sharepoint.norca.click"
)

$ErrorActionPreference = "SilentlyContinue"
$pass = 0; $fail = 0

function Check($desc, [bool]$ok, $fixHint = "") {
    if ($ok) {
        Write-Host "  [OK] $desc" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  [FAIL] $desc" -ForegroundColor Red
        if ($fixHint) { Write-Host "        -> $fixHint" -ForegroundColor DarkYellow }
        $script:fail++
    }
}

Write-Host ""
Write-Host "Module 01 — Admin Lab Check" -ForegroundColor Yellow
Write-Host "===========================" -ForegroundColor Yellow
Write-Host ""

# ── 1. DC01 ──────────────────────────────────────────────────────────────────
Write-Host "[1/5] Domain Controller (DC01)" -ForegroundColor Cyan
Check "DC01 reachable"        (Test-Connection $DCIP -Count 1 -Quiet)
Check "AD DS (NTDS) running"  ((Get-Service NTDS).Status -eq 'Running')  "Start-Service NTDS"
Check "DNS service running"   ((Get-Service DNS).Status  -eq 'Running')  "Start-Service DNS"
Check "Netlogon running"      ((Get-Service Netlogon).Status -eq 'Running') "Start-Service Netlogon"
Write-Host ""

# ── 2. SP01 ──────────────────────────────────────────────────────────────────
Write-Host "[2/5] SharePoint Server (SP01)" -ForegroundColor Cyan
Check "SP01 reachable" (Test-Connection $SPIP -Count 1 -Quiet)

$iisOk = $false
try {
    $r = Invoke-WebRequest -Uri $SPUrl -UseBasicParsing -TimeoutSec 15 -EA Stop
    $iisOk = ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
} catch {
    # 401 = IIS is up but needs auth — that's fine
    $iisOk = ($_.Exception.Response -ne $null)
}
Check "IIS responding on SP01" $iisOk "RDP to SP01, run: Start-Service W3SVC, WAS"

$spDns = Resolve-DnsName "win-norca-sp01.norca.click" -Server $DCIP -EA SilentlyContinue
Check "SP01 in domain DNS" ($null -ne $spDns) "SP01 may not be domain-joined"
Write-Host ""

# ── 3. AD accounts ───────────────────────────────────────────────────────────
Write-Host "[3/5] Scenario Accounts" -ForegroundColor Cyan
$student = Get-ADUser -Filter {SamAccountName -eq "cirtstudent"} -EA SilentlyContinue
$jchen   = Get-ADUser -Filter {SamAccountName -eq "j.chen"}      -EA SilentlyContinue

Check "cirtstudent exists"    ($null -ne $student)            "Run lab_01_setup.ps1"
Check "cirtstudent enabled"   ($student -and $student.Enabled) "Enable-ADAccount cirtstudent"
Check "j.chen exists"         ($null -ne $jchen)              "Run lab_01_setup.ps1"
Check "j.chen enabled"        ($jchen  -and $jchen.Enabled)   "Enable-ADAccount j.chen"
Write-Host ""

# ── 4. Clean state ───────────────────────────────────────────────────────────
Write-Host "[4/5] Clean State (no webshell)" -ForegroundColor Cyan
$wsPresent = $false
try {
    $r = Invoke-WebRequest -Uri "$SPUrl/sites/intranet/Shared%20Documents/help.aspx" `
         -UseBasicParsing -TimeoutSec 10 -EA Stop
    $wsPresent = ($r.StatusCode -eq 200)
} catch {}
Check "SP01 is clean (no webshell)" (-not $wsPresent) "Run lab_01_reset.ps1 to rebuild SP01 from golden image"
Write-Host ""

# ── 5. Kali ──────────────────────────────────────────────────────────────────
Write-Host "[5/5] Kali Attack Machine" -ForegroundColor Cyan
Check "Kali reachable" (Test-Connection $KaliIP -Count 1 -Quiet) "Check Kali01 VM power state in Azure Portal"

$toolsOk = $false
try {
    $result = & ssh "-o" "StrictHostKeyChecking=no" "-o" "ConnectTimeout=10" `
        "kali@$KaliIP" "test -x /opt/raptor/module-01/attack.sh && echo OK" 2>$null
    $toolsOk = ($result -eq "OK")
} catch {}
Check "Attack toolkit on Kali" $toolsOk "Run: lab_01_setup.ps1 (re-stages toolkit)"
Write-Host ""

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "===========================" -ForegroundColor Yellow
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  ALL $total CHECKS PASSED — Lab is ready for student" -ForegroundColor Green
} else {
    Write-Host "  $fail/$total FAILED — Fix above issues before handoff" -ForegroundColor Red
}
Write-Host ""
exit $fail
