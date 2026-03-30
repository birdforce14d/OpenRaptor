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
    [string]$SPUrl = "http://sharepoint.norca.click",
    [int]$WebshellPort = 8080
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
Write-Host "[1/6] Domain Controller (DC01)" -ForegroundColor Yellow
Check "DC01 reachable" ((Test-NetConnection -ComputerName $DCIP -Port 389 -WarningAction SilentlyContinue).TcpTestSucceeded) "DC01 LDAP port 389 not reachable"
Check "AD DS service running" ((Get-Service NTDS -ErrorAction SilentlyContinue).Status -eq 'Running') "AD DS not running"
Check "DNS service running" ((Get-Service DNS -ErrorAction SilentlyContinue).Status -eq 'Running') "DNS not running"
Write-Host ""

# --- 2. SP01 ---
Write-Host "[2/6] SharePoint Server (SP01)" -ForegroundColor Yellow
Check "SP01 reachable" ((Test-NetConnection -ComputerName $SPIP -Port 80 -WarningAction SilentlyContinue).TcpTestSucceeded) "SP01 port 80 not reachable"

$iisOk = $false
try {
    $r = Invoke-WebRequest -Uri $SPUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $iisOk = ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
} catch {
    if ($_.Exception.Response) { $iisOk = $true }  # 401 = IIS is responding, needs auth
}
Check "IIS responding on SP01 (:80)" $iisOk "IIS may not be running — RDP to SP01 and check"

# Domain join check via DNS
$spDns = Resolve-DnsName "win-norca-sp01.norca.click" -Server $DCIP -ErrorAction SilentlyContinue
Check "SP01 domain-joined (DNS A record)" ($null -ne $spDns) "SP01 not found in AD DNS — may not be domain-joined"

# Webshell IIS site check (cmd.aspx on port 8080)
# NOTE: appcmd-based setup required — see sp01-webshell-setup.ps1
$shellOk = $false
$shellOutput = ""
try {
    $r = Invoke-WebRequest -Uri "http://${SPIP}:${WebshellPort}/cmd.aspx?cmd=whoami" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    if ($r.StatusCode -eq 200 -and $r.Content -match "system|nt authority") {
        $shellOk = $true
        $shellOutput = $r.Content.Trim()
    }
} catch {}
Check "Webshell IIS site responding (port $WebshellPort)" $shellOk "Run sp01-webshell-setup.ps1 on SP01 — do NOT use WebAdministration cmdlets via run-command (32-bit WOW64 config mismatch)"
if ($shellOk) { Write-Host "         -> cmd.aspx running as: $shellOutput" -ForegroundColor Cyan }
Write-Host ""

# --- 3. AD Accounts ---
Write-Host "[3/6] Scenario Accounts" -ForegroundColor Yellow
$jchen = Get-ADUser -Filter {SamAccountName -eq "j.chen"} -ErrorAction SilentlyContinue
Check "j.chen account exists" ($null -ne $jchen) "Run lab_01_setup.ps1 to create"

if ($jchen) {
    Check "j.chen is enabled" ($jchen.Enabled) "Account is disabled — run: Enable-ADAccount j.chen"
}
Write-Host ""

# --- 4. Clean state ---
Write-Host "[4/6] Clean State" -ForegroundColor Yellow
$shellExists = $false
try {
    $password = ConvertTo-SecureString "CirtApacStudent2026" -AsPlainText -Force
    $cred = New-Object PSCredential("NORCA\j.chen", $password)
    $r = Invoke-WebRequest -Uri "$SPUrl/Shared%20Documents/help.aspx" -Credential $cred -UseBasicParsing -ErrorAction Stop
    $shellExists = $true
} catch {}
Check "SP01 is clean (no webshell)" (-not $shellExists) "help.aspx already exists — run lab_01_reset.ps1"
Write-Host ""

# --- 5. ShellSite (IIS port 8080 + cmd.aspx) ---
Write-Host "[5/6] ShellSite (SP01 port 8080)" -ForegroundColor Yellow

$shellSiteOk = $false
try {
    $r = Invoke-WebRequest -Uri "http://${SPIP}:8080/cmd.aspx?cmd=whoami" `
        -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    $shellSiteOk = ($r.Content -match "nt authority|iis apppool|system")
} catch {}
Check "ShellSite responding on port 8080" $shellSiteOk `
    "Run lab_01_setup.ps1 to provision ShellSite, or see admin guide for manual steps"
Write-Host ""

# --- 6. Kali ---
Write-Host "[6/6] Kali Attack Machine" -ForegroundColor Yellow
Check "Kali reachable" ((Test-NetConnection -ComputerName $KaliIP -Port 22 -WarningAction SilentlyContinue).TcpTestSucceeded) "Kali SSH port 22 not reachable"

# Check attack scripts via SSH (best-effort)
$toolsOk = $false
try {
    $result = ssh "kali@$KaliIP" "test -x /opt/raptor/module-01/attack.sh && test -x /opt/raptor/module-01/preflight.sh && echo OK" 2>$null
    $toolsOk = ($result -eq "OK")
} catch {}
if ($toolsOk) {
    Check "Attack scripts deployed to Kali" $true
} else {
    Check "Attack scripts deployed to Kali" $false "Copy attack.sh + preflight.sh to /opt/raptor/module-01/ on Kali"
}
Write-Host ""

# --- Summary ---
Write-Host "============================" -ForegroundColor Yellow
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  ALL $total CHECKS PASSED" -ForegroundColor Green
    Write-Host "  Lab is ready. Hand off to student." -ForegroundColor Green
} else {
    Write-Host "  $fail/$total CHECKS FAILED" -ForegroundColor Red
    Write-Host "  Fix issues above before handing to student." -ForegroundColor Red
}
Write-Host ""
