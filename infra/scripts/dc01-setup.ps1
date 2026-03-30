# =============================================================================
# LEGACY NOTICE: This script is NOT used in the current OD@CIRT.APAC deployment.
# Current deployment uses the dc01-base-specialized golden image (ARM template
# + managed identity + dc01-presetup.ps1 via Custom Script Extension).
# This script documents the self-hosted path for admins deploying without
# the golden image. See docs/self-deployment-guide.md for context.
# =============================================================================

# =============================================================================
# Module-01: DC01 Setup Script (Part 1)
# Downloaded and run by CustomScriptExtension at VM provisioning time
# Step 1: Rename, AD DS install, forest promotion
# Post-reboot: dc01-post-reboot.ps1 runs via RunOnce
# =============================================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "Continue"
Start-Transcript -Path "C:\dc01-setup.log" -Append -Force

# ---- CONFIG ----
$DomainName    = "norca.click"
$NetbiosName   = "NORCA"
$SafeModePass  = ConvertTo-SecureString "CirtApacAdm!n2026" -AsPlainText -Force

Write-Host "[1/4] Renaming computer to DC01..."
try { Rename-Computer -NewName "DC01" -Force -ErrorAction Stop } catch { Write-Host "Rename skipped: already DC01" }

Write-Host "[2/4] Installing AD DS + DNS roles..."
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools

Write-Host "[3/4] Registering post-reboot script via RunOnce..."
$postRebootUrl = "https://raw.githubusercontent.com/birdforce14d/OpenRaptor/main/infra/scripts/dc01-post-reboot.ps1"
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" `
    -Name "DC01PostReboot" `
    -Value "powershell -ExecutionPolicy Unrestricted -NonInteractive -Command `"(New-Object Net.WebClient).DownloadFile('$postRebootUrl','C:\dc01-post-reboot.ps1'); & C:\dc01-post-reboot.ps1`" > C:\dc01-post-reboot.log 2>&1"

Write-Host "[4/4] Promoting to Domain Controller (will reboot automatically)..."
Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -SafeModeAdministratorPassword $SafeModePass `
    -InstallDns:$true `
    -Force:$true

Stop-Transcript
