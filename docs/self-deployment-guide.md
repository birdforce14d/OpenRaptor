# Self-Deployment Guide — OpenRaptor Cyber Range

_Deploy the full OpenRaptor cyber range from scratch in your own Azure subscription. No golden images or Terraform required._

> **Estimated time:** 2–3 hours (manual steps + provisioning waits)
>
> **Estimated monthly cost:** ~$275/month (Australia East, 8h/day with auto-shutdown)

---

## Overview

This guide walks you through building the entire lab environment manually using Azure CLI and PowerShell — creating VMs from Azure Marketplace images, installing Active Directory, SharePoint 2019, and setting up Kali Linux.

If OD@CIRT.APAC has deployed your lab, **you don't need this guide** — see the [Admin Guide](admin-guide.md) instead.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Azure subscription | Contributor or Owner role |
| Azure CLI | v2.50+ ([install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)) |
| VM quota | 8+ vCPUs in your target region |
| Browser | Chrome or Edge (for Azure Bastion access) |

---

## Network Architecture

| Subnet | CIDR | Purpose | VMs |
|--------|------|---------|-----|
| snet-identity | 10.10.1.0/24 | Domain services | DC01 (10.10.1.10) |
| snet-servers | 10.10.2.0/24 | Application servers | SP01 (10.10.2.10) |
| snet-attacker | 10.10.3.0/24 | Attack simulation | Kali01 (10.10.3.10) |
| AzureBastionSubnet | 10.10.4.0/26 | Bastion ingress | Azure Bastion |

> ⚠️ **No VMs have public IP addresses.** All access is via Azure Bastion only.

---

## Step 1 — Create Resource Group and Network

```
az group create --name rg-cirtlab-core --location australiaeast
```

```
az network vnet create --resource-group rg-cirtlab-core --name vnet-cirtlab --address-prefix 10.10.0.0/16 --location australiaeast
```

```
az network vnet subnet create --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name snet-identity --address-prefix 10.10.1.0/24
```

```
az network vnet subnet create --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name snet-servers --address-prefix 10.10.2.0/24
```

```
az network vnet subnet create --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name snet-attacker --address-prefix 10.10.3.0/24
```

```
az network vnet subnet create --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name AzureBastionSubnet --address-prefix 10.10.4.0/26
```

### Create NSGs

```
az network nsg create --resource-group rg-cirtlab-core --name nsg-identity --location australiaeast
```

```
az network nsg create --resource-group rg-cirtlab-core --name nsg-servers --location australiaeast
```

```
az network nsg create --resource-group rg-cirtlab-core --name nsg-attacker --location australiaeast
```

Allow ICMP between subnets:

```
az network nsg rule create --resource-group rg-cirtlab-core --nsg-name nsg-identity --name AllowICMPVNet --priority 200 --protocol Icmp --direction Inbound --access Allow --source-address-prefixes VirtualNetwork --destination-address-prefixes VirtualNetwork
```

```
az network nsg rule create --resource-group rg-cirtlab-core --nsg-name nsg-servers --name AllowICMPVNet --priority 200 --protocol Icmp --direction Inbound --access Allow --source-address-prefixes VirtualNetwork --destination-address-prefixes VirtualNetwork
```

```
az network nsg rule create --resource-group rg-cirtlab-core --nsg-name nsg-attacker --name AllowICMPVNet --priority 200 --protocol Icmp --direction Inbound --access Allow --source-address-prefixes VirtualNetwork --destination-address-prefixes VirtualNetwork
```

Associate NSGs with subnets:

```
az network vnet subnet update --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name snet-identity --network-security-group nsg-identity
```

```
az network vnet subnet update --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name snet-servers --network-security-group nsg-servers
```

```
az network vnet subnet update --resource-group rg-cirtlab-core --vnet-name vnet-cirtlab --name snet-attacker --network-security-group nsg-attacker
```

---

## Step 2 — Deploy Azure Bastion

```
az network public-ip create --resource-group rg-cirtlab-core --name pip-bastion --sku Standard --allocation-method Static --location australiaeast
```

```
az network bastion create --resource-group rg-cirtlab-core --name bastion-cirtlab --public-ip-address pip-bastion --vnet-name vnet-cirtlab --sku Basic --location australiaeast
```

> ⏳ Bastion takes ~5 minutes to deploy.

---

## Step 3 — Deploy Log Analytics Workspace

```
az monitor log-analytics workspace create --resource-group rg-cirtlab-core --workspace-name law-cirtlab --location australiaeast --retention-in-days 30
```

---

## Step 4 — Deploy DC01 (Domain Controller)

### Create the VM

```
az network nic create --resource-group rg-cirtlab-core --name dc01-nic --vnet-name vnet-cirtlab --subnet snet-identity --private-ip-address 10.10.1.10 --network-security-group nsg-identity
```

```
az vm create --resource-group rg-cirtlab-core --name dc01 --nics dc01-nic --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest --size Standard_D2s_v3 --admin-username cirtadmin --admin-password "Norca@2024!" --os-disk-size-gb 128 --no-wait
```

> ⏳ Wait for the VM to be running before continuing.

### Install Active Directory Domain Services

Connect to DC01 via Bastion, open PowerShell as Administrator:

```powershell
# Install AD DS and DNS
Install-WindowsFeature -Name AD-Domain-Services,DNS -IncludeManagementTools

# Promote to domain controller
Install-ADDSForest `
    -DomainName "norca.click" `
    -DomainNetbiosName "NORCA" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "Norca@2024!" -AsPlainText -Force) `
    -InstallDns:$true `
    -Force:$true
```

The VM will restart automatically. Wait ~5 minutes, then reconnect via Bastion.

### Create Service and User Accounts

After reconnecting to DC01 as `NORCA\cirtadmin`:

```powershell
# Service account for SharePoint (dedicated password — do not change)
$svcPass = ConvertTo-SecureString "Norca@2024!" -AsPlainText -Force
New-ADUser -Name "svc-sp-farm" -SamAccountName "svc-sp-farm" -UserPrincipalName "svc-sp-farm@norca.click" -AccountPassword $svcPass -Enabled $true -PasswordNeverExpires $true -Description "SharePoint Farm Service Account"
Add-ADGroupMember -Identity "Domain Admins" -Members "svc-sp-farm"

# Student login account
$studentPass = ConvertTo-SecureString "CirtApacStudent2026" -AsPlainText -Force
New-ADUser -Name "CIRT Student" -SamAccountName "cirtstudent" -UserPrincipalName "cirtstudent@norca.click" -AccountPassword $studentPass -Enabled $true -PasswordNeverExpires $true -Description "Student login account"
Add-ADGroupMember -Identity "Remote Desktop Users" -Members "cirtstudent"

# Scenario account (compromised Finance analyst — not for student login)
New-ADUser -Name "Jenny Chen" -GivenName "Jenny" -Surname "Chen" -SamAccountName "j.chen" -UserPrincipalName "j.chen@norca.click" -AccountPassword $studentPass -Enabled $true -PasswordNeverExpires $true -Description "Finance Analyst — scenario account"
```

### Add DNS Record for SharePoint

```powershell
Add-DnsServerResourceRecordA -ZoneName "norca.click" -Name "sharepoint" -IPv4Address "10.10.2.10"
```

---

## Step 5 — Deploy SP01 (SharePoint Server)

### Create the VM

```
az network nic create --resource-group rg-cirtlab-core --name sp01-nic --vnet-name vnet-cirtlab --subnet snet-servers --private-ip-address 10.10.2.10 --network-security-group nsg-servers
```

```
az vm create --resource-group rg-cirtlab-core --name sp01 --nics sp01-nic --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest --size Standard_D4s_v3 --admin-username cirtadmin --admin-password "Norca@2024!" --os-disk-size-gb 128 --no-wait
```

### Configure DNS and Join Domain

Connect to SP01 via Bastion:

```powershell
# Point DNS to DC01
Set-DnsClientServerAddress -InterfaceAlias "Ethernet*" -ServerAddresses "10.10.1.10"

# Join domain
$cred = New-Object PSCredential("NORCA\cirtadmin", (ConvertTo-SecureString "Norca@2024!" -AsPlainText -Force))
Add-Computer -DomainName "norca.click" -Credential $cred -Force -Restart
```

Wait for restart, reconnect via Bastion as `NORCA\cirtadmin`.

### Install SharePoint 2019

> ⚠️ SharePoint 2019 installation is a multi-step process. For the full procedure, see the [official Microsoft documentation](https://learn.microsoft.com/en-us/sharepoint/install/install-sharepoint-server-2019).

**High-level steps:**

1. Download and install **SQL Server 2019 Express** with named instance `SHAREPOINT`
2. Download **SharePoint 2019** prerequisites installer and run it
3. Install SharePoint 2019
4. Run the **SharePoint Products Configuration Wizard**:
   - New farm → SQL instance: `.\SHAREPOINT`
   - Farm account: `NORCA\svc-sp-farm` / password: `Norca@2024!`

**Post-install — create web application and site collection:**

```powershell
Add-PSSnapin Microsoft.SharePoint.PowerShell

# Register managed account
$svcCred = New-Object PSCredential("NORCA\svc-sp-farm", (ConvertTo-SecureString "Norca@2024!" -AsPlainText -Force))
New-SPManagedAccount -Credential $svcCred

# Create web application
New-SPWebApplication -Name "NORCA Intranet" -Port 80 -HostHeader "sharepoint.norca.click" -Url "http://sharepoint.norca.click" -ApplicationPool "SharePoint - 80" -ApplicationPoolAccount (Get-SPManagedAccount "NORCA\svc-sp-farm") -DatabaseServer ".\SHAREPOINT" -DatabaseName "WSS_Content_Intranet"

# Create root site collection
New-SPSite -Url "http://sharepoint.norca.click" -OwnerAlias "NORCA\cirtadmin" -Template "STS#0" -Name "NORCA Intranet"
```

**Verify:**
```powershell
Invoke-WebRequest -Uri "http://localhost" -UseDefaultCredentials -UseBasicParsing | Select-Object StatusCode
# Expected: 200
```

---

## Step 6 — Deploy Kali01 (Attacker VM)

### Accept Marketplace Terms

```
az vm image terms accept --publisher kali-linux --offer kali --plan kali-2025-4
```

### Create the VM

```
az network nic create --resource-group rg-cirtlab-core --name kali01-nic --vnet-name vnet-cirtlab --subnet snet-attacker --private-ip-address 10.10.3.10 --network-security-group nsg-attacker
```

```
az vm create --resource-group rg-cirtlab-core --name kali01 --nics kali01-nic --image kali-linux:kali:kali-2025-4:latest --size Standard_D2s_v3 --admin-username kali --admin-password "Norca@2024!" --os-disk-size-gb 64 --plan-name kali-2025-4 --plan-product kali --plan-publisher kali-linux --no-wait
```

### Install Attack Toolkit

Connect to Kali01 via Bastion (SSH):

```bash
sudo apt-get update && sudo apt-get install -y curl wget nmap

sudo mkdir -p /opt/raptor/module-01/payloads
sudo chown -R kali:kali /opt/raptor

# Download Module 01 scripts from OpenRaptor
wget -q "https://raw.githubusercontent.com/birdforce14d/OpenRaptor/main/scenarios/module-01-webshell/attack.sh" -O /opt/raptor/module-01/attack.sh
wget -q "https://raw.githubusercontent.com/birdforce14d/OpenRaptor/main/scenarios/module-01-webshell/student/check-lab-01.sh" -O /opt/raptor/module-01/check-lab.sh
chmod +x /opt/raptor/module-01/*.sh
```

---

## Step 7 — Configure Auto-Shutdown

```
az vm auto-shutdown --resource-group rg-cirtlab-core --name dc01 --time 1900
```

```
az vm auto-shutdown --resource-group rg-cirtlab-core --name sp01 --time 1900
```

```
az vm auto-shutdown --resource-group rg-cirtlab-core --name kali01 --time 1900
```

---

## Step 8 — Verify the Lab

### From DC01 (PowerShell):

```powershell
Get-Service NTDS,DNS | Select Name,Status
(Get-ADDomain).DNSRoot
Get-ADUser -Filter {SamAccountName -eq "cirtstudent" -or SamAccountName -eq "j.chen" -or SamAccountName -eq "svc-sp-farm"} | Select SamAccountName
Resolve-DnsName sharepoint.norca.click
```

### From SP01 (PowerShell):

```powershell
Get-Service SPTimerV4,W3SVC | Select Name,Status
Invoke-WebRequest -Uri "http://localhost" -UseDefaultCredentials -UseBasicParsing | Select StatusCode
```

### From Kali01 (bash):

```bash
ping -c 1 10.10.1.10 && echo "DC01: OK" || echo "DC01: FAIL"
ping -c 1 10.10.2.10 && echo "SP01: OK" || echo "SP01: FAIL"
ls -la /opt/raptor/module-01/
```

All checks should pass. Your lab is ready.

---

## Credential Reference

| Account | Password | Purpose |
|---------|----------|---------|
| `NORCA\cirtadmin` | `Norca@2024!` | Domain Admin, lab administrator |
| `NORCA\svc-sp-farm` | `Norca@2024!` | SharePoint farm service account — **dedicated, do not change** |
| `NORCA\cirtstudent` | `CirtApacStudent2026` | Student login — lab exercises |
| `NORCA\j.chen` | `CirtApacStudent2026` | Scenario character (compromised Finance analyst) |

> ⚠️ **`svc-sp-farm` uses `Norca@2024!`** — this is a dedicated service account password, separate from admin and student credentials. All SharePoint services (SPTimerV4, SPAdminV4, SPWriterV4) and IIS app pools (`SharePoint - 80`, `SecurityTokenServiceApplicationPool`, `SharePoint Web Services System`) run under this account.

---

## Troubleshooting

### Windows Server Activation Warning

After deployment, Windows Server VMs may show _"Windows isn't activated"_. Fix on each affected VM:

```powershell
slmgr /skms kms.core.windows.net:1688
slmgr /ato
```

### SharePoint returns HTTP 500 after reboot

Most common cause: IIS app pools lost their credentials. Fix on SP01:

```powershell
Import-Module WebAdministration
$pools = @("SharePoint - 80", "SecurityTokenServiceApplicationPool", "SharePoint Web Services System")
foreach ($pool in $pools) {
    Set-ItemProperty "IIS:\AppPools\$pool" -Name processModel.userName -Value "NORCA\svc-sp-farm"
    Set-ItemProperty "IIS:\AppPools\$pool" -Name processModel.password -Value "Norca@2024!"
}
sc.exe config SPTimerV4 obj= "NORCA\svc-sp-farm" password= "Norca@2024!"
sc.exe config SPAdminV4 obj= "NORCA\svc-sp-farm" password= "Norca@2024!"
sc.exe config SPWriterV4 obj= "NORCA\svc-sp-farm" password= "Norca@2024!"
iisreset /restart
Start-Service SPTimerV4
```

### SharePoint returns HTTP 401

Expected when testing with `Invoke-WebRequest` in non-interactive mode. SharePoint uses NTLM/Kerberos authentication. Test from an interactive RDP browser session instead. Use `http://localhost` with `-UseDefaultCredentials` from SP01 itself for scripted checks.

### SP01 cannot join domain

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet*" -ServerAddresses "10.10.1.10"
Test-NetConnection -ComputerName 10.10.1.10 -Port 389
```

### Kali cannot reach other VMs

Check NSG rules allow ICMP and verify subnet-NSG associations.

---

## Next Steps

1. **Start Module 01** — [SharePoint Webshell Detection Lab Guide](lab-guide/01-sharepoint-webshell.md)
2. **Student access** — students RDP via Bastion as `NORCA\cirtstudent` / `CirtApacStudent2026`
3. **Reset between students** — run `lab_01_reset.ps1` from DC01 (see [Admin Guide](admin-guide.md))

---

_OpenRaptor Cyber Range — OD@CIRT.APAC_
