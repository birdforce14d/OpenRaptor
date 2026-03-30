# Admin Deployment Guide - OpenRaptor Cyber Range

This guide is for administrators deploying the OpenRaptor Cyber Range in a new Azure tenant.

> ## 🚀 Lab deployed by OD@CIRT.APAC?
>
> If OD@CIRT.APAC has deployed and handed over this lab environment to you, **your lab is ready - no setup required.**
>
> | Role | Go to |
> |------|-------|
> | 🧑‍💼 **Tenant Admin** | Jump to [Lab Administration - Per-Module Scripts](#lab-administration--per-module-scripts) - everything is pre-deployed, just run and reset modules |
> | 🎓 **Student** | [Student Lab Guide](lab-guide/01-sharepoint-webshell.md) - start your training directly |
>
> ⬇️ **Steps 1-8 below** are only needed if you are self-hosting and deploying the lab from scratch in your own Azure subscription.

---

## Prerequisites

### Azure Requirements
- Active Azure subscription with **Contributor** role (or Owner)
- Entra ID tenant with ability to register applications
- Sufficient quota in your target region:
  - At least **6 vCPUs** (Standard_D2s_v3 × 3 VMs)
  - **1 Bastion** deployment
  - **1 Public IP** (for Bastion only)

### Local Machine Requirements
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az` v2.50+)
- [Terraform](https://developer.hashicorp.com/terraform/install) (v1.5+)
- Git

### Licensing Requirements
- **Entra ID P1** (minimum) - for conditional access and risk-based sign-in logs
- **Microsoft 365 E3 or SharePoint Online Plan 2** - for SharePoint and unified audit log
- **MDE** - optional. If available, Microsoft Defender for Endpoint provides device-level telemetry and timeline analysis. Not required for core labs

---

---

## Credential Reference (Canonical)

> **Do not guess passwords. This table is the system of record. Updated: 2026-03-09**

| Class | Account | Password | Notes |
|-------|-----------|----------|-------|
| Domain Admin | cirtadmin | CirtApac2024! | Local and domain admin on all VMs |
| Student login | cirtstudent | CirtApac2024! | On-prem AD only — cannot log in to Azure Portal |
| SharePoint SVC | svc-sp-farm | Norca@2024! | Baked into SP01 image — do not change |
| SharePoint SVC | svc-sp-app | Norca@2024! | Baked into SP01 image — do not change |

> ⚠️ Service accounts (`svc-sp-farm`, `svc-sp-app`) must use `Norca@2024!` - this is baked into the SP01 golden image. Using any other password will cause SharePoint services to fail on startup.


## Step 1 - Create a Service Principal

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Create the service principal
az ad sp create-for-rbac \
  --name "sp-cirtlab-deploy" \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID>
```

Save the output - you'll need it in Step 3:
```json
{
  "appId":       "YOUR_CLIENT_ID",
  "password":    "YOUR_CLIENT_SECRET",
  "tenant":      "YOUR_TENANT_ID"
}
```

> ⚠️ **Security:** Store the secret in Azure Key Vault or a secrets manager. Never commit it to Git.

---

## Step 2 - Clone the Repo

```bash
git clone https://github.com/<your-org>/OpenRaptor.git
cd OpenRaptor
```

---

## Step 3 - Configure Deployment Variables

Copy the example vars file and fill in your values:

```bash
cp infra-tf/terraform.tfvars.example infra-tf/terraform.tfvars
```

Edit `infra-tf/terraform.tfvars`:

```hcl
# Target Azure tenant and subscription
subscription_id = "YOUR_SUBSCRIPTION_ID"
location        = "australiaeast"        # Change to your preferred region

# Resource groups (names are customisable)
rg_network  = "rg-cirtlab-network"
rg_core     = "rg-cirtlab-core"
rg_attacker = "rg-cirtlab-attacker"

# VM admin credentials
admin_username = "cirtadmin"
# admin_password set via environment variable - see below

# Golden image IDs - Community Gallery (provided by OD@CIRT.APAC out-of-band)
sp01_image_id = "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/sp01-module01-student/Versions/1.0.0"
dc01_image_id = "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/dc01-base-specialized/Versions/1.0.0"

# Kali post-deploy setup script (pull from OpenRaptor - public)

# Infrastructure
bastion_sku   = "Basic"
dns_zone_name = "norca.click"
vm_size       = "Standard_D2s_v3"

# SP01 private IP (snet-target-module01 = 10.10.3.0/24)
sp01_private_ip = "10.10.3.10"

# Tags applied to all resources
tags = {
  environment = "lab"
  module      = "shared"
  owner       = "cirt"
  blastRadius = "zero"
  ttl         = "2026-12-31"
}
```

Set your admin password as an environment variable (do not put it in the vars file):

```bash
# Bash
export TF_VAR_admin_password="CirtApacAdm!n2026"

# PowerShell
$env:TF_VAR_admin_password = "CirtApacAdm!n2026"
```

> ⚠️ **Never commit `terraform.tfvars` to Git.** It contains your subscription ID and is in `.gitignore` by default.

---

## Step 4 - Authenticate to Azure

Login with the service principal created in Step 1:

```bash
# Bash
az login --service-principal \
  --username  "$ARM_CLIENT_ID" \
  --password  "$ARM_CLIENT_SECRET" \
  --tenant    "$ARM_TENANT_ID"

# PowerShell
az login --service-principal `
  --username  $env:ARM_CLIENT_ID `
  --password  $env:ARM_CLIENT_SECRET `
  --tenant    $env:ARM_TENANT_ID

az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

Or log in interactively if you have Owner/Contributor access:

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

---

## Step 5 - Deploy Infrastructure (Terraform)

All infrastructure is deployed from the single `infra-tf/` directory. One `terraform apply` creates everything: networking, VMs, Bastion, Log Analytics, DNS, and policy.

```bash
cd infra-tf

# Initialise (downloads providers: azurerm ~>4.0, azapi ~>2.0)
terraform init

# Preview - review carefully before applying
terraform plan -out=tfplan

# Apply - takes approximately 45-55 minutes (includes DC01 AD provisioning, 15-min wait, SP01 domain join and postsetup)
terraform apply tfplan
```

Resources created:

|--------|-----------|

> ⏳ VM provisioning from golden images takes **5-10 minutes** per VM. Total deployment: **15-25 minutes**.

### Golden Images

|-------|-----|--------|-------------|

> 📌 Community Gallery name (`<COMMUNITY_GALLERY_NAME>`) is provided by OD@CIRT.APAC directly to authorised deployers. It is not published in this repo.

---

## Step 5 (Alternative) - Manual Deployment via `az vm create`

If you prefer not to use Terraform, or need to redeploy individual VMs, use `az vm create` directly.

> **Prerequisites:** VNet, subnets, and NSGs must already exist. Deploy networking with Terraform first (`terraform apply -target module.network`), then use the commands below for VMs.

### DC01

```bash
# Bash
az vm create \
  --resource-group rg-cirtlab-core \
  --name dc01 \
  --image "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/dc01-base-specialized/Versions/1.0.0" \
  --size Standard_D2s_v3 \
  --admin-username cirtadmin \
  --admin-password "<YOUR_ADMIN_PASSWORD>" \
  --vnet-name vnet-cirtlab-base \
  --subnet snet-core \
  --private-ip-address 10.10.1.10 \
  --public-ip-address "" \
  --location australiaeast

# PowerShell
az vm create `
  --resource-group rg-cirtlab-core `
  --name dc01 `
  --image "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/dc01-base-specialized/Versions/1.0.0" `
  --size Standard_D2s_v3 `
  --admin-username cirtadmin `
  --admin-password "<YOUR_ADMIN_PASSWORD>" `
  --vnet-name vnet-cirtlab-base `
  --subnet snet-core `
  --private-ip-address 10.10.1.10 `
  --public-ip-address "" `
  --location australiaeast
```

### SP01 (Module 01 - noWS image)

```bash
# Bash
az vm create \
  --resource-group rg-cirtlab-core \
  --name win-norca-sp01 \
  --image "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/sp01-module01-student/Versions/1.0.0" \
  --size Standard_D2s_v3 \
  --admin-username cirtadmin \
  --admin-password "<YOUR_ADMIN_PASSWORD>" \
  --vnet-name vnet-cirtlab-base \
  --subnet snet-target-module01 \
  --private-ip-address 10.10.3.10 \
  --public-ip-address "" \
  --location australiaeast

# PowerShell
az vm create `
  --resource-group rg-cirtlab-core `
  --name win-norca-sp01 `
  --image "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/sp01-module01-student/Versions/1.0.0" `
  --size Standard_D2s_v3 `
  --admin-username cirtadmin `
  --admin-password "<YOUR_ADMIN_PASSWORD>" `
  --vnet-name vnet-cirtlab-base `
  --subnet snet-target-module01 `
  --private-ip-address 10.10.3.10 `
  --public-ip-address "" `
  --location australiaeast
```

### Kali01 (Marketplace)

```bash
# Accept Marketplace terms first (one-time per subscription)
az vm image terms accept \
  --publisher kali-linux \
  --offer kali \
  --plan kali-2025-4

# Bash
az vm create \
  --resource-group rg-cirtlab-attacker \
  --name kali01 \
  --image "kali-linux:kali:kali-2025-4:latest" \
  --size Standard_D2s_v3 \
  --admin-username cirtadmin \
  --admin-password "<YOUR_ADMIN_PASSWORD>" \
  --vnet-name vnet-cirtlab-base \
  --subnet snet-attacker \
  --private-ip-address 10.10.2.10 \
  --public-ip-address "" \
  --location australiaeast

# PowerShell
az vm create `
  --resource-group rg-cirtlab-attacker `
  --name kali01 `
  --image "kali-linux:kali:kali-2025-4:latest" `
  --size Standard_D2s_v3 `
  --admin-username cirtadmin `
  --admin-password "<YOUR_ADMIN_PASSWORD>" `
  --vnet-name vnet-cirtlab-base `
  --subnet snet-attacker `
  --private-ip-address 10.10.2.10 `
  --public-ip-address "" `
  --location australiaeast
```

---

## Step 6 - Post-Deploy: SharePoint Service Accounts

After DC01 and SP01 are running, verify SharePoint services start correctly. The golden image has `svc-sp-farm` and `svc-sp-app` baked with password `Norca@2024!`.

Connect to SP01 via Bastion and run:

```powershell
# On SP01 - verify SharePoint services are running
Get-Service | Where-Object { $_.Name -like "SP*" } | Select Name, Status

# If services are stopped, reset service account credentials:
$svcPass = "Norca@2024!"
sc.exe config SPTimerV4  obj= "NORCA\svc-sp-farm" password= $svcPass
sc.exe config SPWriterV4 obj= "NORCA\svc-sp-farm" password= $svcPass
sc.exe config SPAdminV4  obj= "NORCA\svc-sp-farm" password= $svcPass
net start SPTimerV4
```

> ⚠️ **`svc-sp-farm` and `svc-sp-app` passwords are permanently `Norca@2024!`** - baked into the golden image. Do not change or rotate these. See [Credential Reference](#credential-reference-canonical).

---

## Step 7 - Lab Module Setup

After all VMs are running, stage the scenario toolkit for Module 01. Run this from DC01:

```powershell
# On DC01 - stage Module 01 toolkit
# Downloads from OpenRaptor, stages on Kali01, seeds j.chen account
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/<your-org>/OpenRaptor/main/scenarios/module-01-webshell/admin/lab_01_setup.ps1" -OutFile "C:\lab_01_setup.ps1"
.\lab_01_setup.ps1
```

Expected output:
```
[OK] DC01 reachable
[OK] SP01 reachable - HTTP 200 on http://sharepoint.norca.click
[OK] j.chen account created (or already exists)
[OK] Kali01 toolkit staged at /opt/raptor/lab-01/
[OK] SP01 in clean state (no webshell present)
--- Lab 01 setup: READY ---
```

> Run once after initial deployment. Not required after SP01-only resets (`lab_01_reset.ps1` handles SP01 state automatically).

---

## Step 8 - Configure Student Access

### Create Student Account

```bash
# Azure CLI - create cirtstudent in on-prem AD via DC01 (Bastion session on DC01)
New-ADUser -Name "cirtstudent" `
  -UserPrincipalName "cirtstudent@norca.click" `
  -AccountPassword (ConvertTo-SecureString "CirtApacStudent2026" -AsPlainText -Force) `
  -PasswordNeverExpires $true `
  -Enabled $true
```

### Assign Log Analytics Reader Role

```bash
# Bash
az role assignment create \
  --assignee "cirtstudent@norca.click" \
  --role "Log Analytics Reader" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-cirtlab-core

> **Note (OD@CIRT.APAC deployments):** The  account is created automatically during DC01 provisioning. Skip this manual step if your lab was deployed by OD@CIRT.APAC.

# PowerShell
az role assignment create `
  --assignee "cirtstudent@norca.click" `
  --role "Log Analytics Reader" `
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-cirtlab-core
```

### Share Bastion Access

Students connect via Azure Bastion - no public IPs, no VPN required:

1. Azure Portal → Resource Group `rg-cirtlab-core`
2. Select `win-norca-sp01` → **Connect** → **Bastion**
3. Provide credentials from your lab handover document

> 💡 Pin a Portal dashboard with direct Bastion links to each VM and the Log Analytics Workspace for student convenience.

## Cost Management

### Estimated Monthly Cost (australiaeast, all VMs running 8h/day)

|---|---|

> Costs vary by region and usage. Bastion is the biggest cost driver - consider [Bastion Developer SKU](https://learn.microsoft.com/azure/bastion/quickstart-developer) to reduce costs.

### Auto-Shutdown
Auto-shutdown is **not configured by default** in the Terraform deployment. To enable nightly shutdown at 19:00 UTC, run `az vm auto-shutdown --resource-group <RG> --name <VM> --time 1900` for each VM, or configure via Azure Portal → VM → Auto-shutdown.

### Destroy the Lab
```bash
cd infra-tf

# Bash
terraform destroy -auto-approve

# PowerShell
terraform destroy -auto-approve
```

> ⚠️ This destroys **all** lab resources - VMs, networking, Bastion, Log Analytics. Golden images in the Community Gallery are **not** deleted (they live in the source subscription). You can redeploy at any time.

---

## Troubleshooting

### SP01 SharePoint not responding after reboot

If SP01 becomes unresponsive after a reboot, use the reset script to rebuild from the golden image:

```powershell
# On DC01 as Domain Admin
.\scenarios\module-01-webshell\admin\lab_01_reset.ps1
```

See the **Recovery Plan** section for manual rebuild steps if Terraform is unavailable.

### SP01 can't join domain
```powershell
# Verify DNS points to DC01
Set-DnsClientServerAddress -InterfaceAlias "Ethernet*" -ServerAddresses "10.10.1.10"

# Test connectivity
Test-NetConnection -ComputerName 10.10.1.10 -Port 389

# Attempt rejoin
$cred = Get-Credential  # DOMAIN\cirtadmin
Add-Computer -DomainName "{{DOMAIN}}" -Credential $cred -Force -Restart
```

### ShellSite (port 8080) — Troubleshooting Matrix

`ShellSite` is the Module 01 scenario artefact — an IIS site on port 8080 serving `cmd.aspx`. It runs as `NT AUTHORITY\SYSTEM` (LocalSystem app pool — lab-only, intentional). The table below covers every failure mode observed in production.

#### Step 1 — Validate current state (run on SP01 as admin)

```powershell
# 1. Port listener
netstat -ano | findstr ":8080"
# Expected: TCP  0.0.0.0:8080  LISTENING  and  TCP  [::]:8080  LISTENING

# 2. IIS config (use appcmd — NOT Get-WebSite, which may read wrong config)
C:\Windows\System32\inetsrv\appcmd.exe list site "ShellSite"
C:\Windows\System32\inetsrv\appcmd.exe list apppool "ShellPool"
# Expected: state:Started for both

# 3. TCP reachability
Test-NetConnection -ComputerName localhost -Port 8080
# Expected: TcpTestSucceeded : True

# 4. Functional test
curl.exe "http://localhost:8080/cmd.aspx?cmd=whoami"
# Expected: nt authority\system
```

#### Step 2 — Symptom → Cause → Fix

|---------|-------|-----|

#### Fix A — Full rebuild (recommended, idempotent)

Run directly on SP01 in an **elevated PowerShell** session (RDP):

```powershell
# Option 1: Use the Woodpecker script (WebAdministration — only safe when run directly on SP01, not via run-command)
powershell -ExecutionPolicy Bypass -File ".\scripts\deploy-shellsite.ps1"

# Option 2: Use Shrike's appcmd script (safe via run-command AND direct)
powershell -ExecutionPolicy Bypass -File ".\scenarios\module-01-webshell\admin\sp01-webshell-setup.ps1"
```

Both scripts are idempotent — safe to run on an already-configured machine.

#### Fix B — Quick web.config recreate (500.19 only)

```powershell
@'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.web>
    <compilation debug="true" targetFramework="4.0" />
    <httpRuntime targetFramework="4.0" />
  </system.web>
</configuration>
'@ | Set-Content -Path "C:\inetpub\shell\web.config" -Encoding UTF8
```

Then verify: `curl.exe http://localhost:8080/cmd.aspx?cmd=whoami`

#### ⚠️ WOW64 config mismatch — critical note for remote automation

`az vm run-command` spawns a **32-bit WOW64 PowerShell process**. `Import-Module WebAdministration` in that context writes to:
```
C:\Windows\SysWOW64\inetsrv\config\applicationHost.config
```
IIS reads from:
```
C:\Windows\System32\inetsrv\config\applicationHost.config
```
These are **different files**. Sites created via WebAdministration in a run-command context are invisible to IIS and to interactive sessions.

**Rule:** When automating IIS config remotely via `az run-command`, always use `C:\Windows\System32\inetsrv\appcmd.exe` directly. `sp01-webshell-setup.ps1` follows this rule. `deploy-shellsite.ps1` uses WebAdministration and must only be run via RDP (direct session on SP01).

### Log Analytics not receiving data
- Check VM extensions are installed: Portal → VM → Extensions
- Verify NSG allows outbound 443 from monitoring subnet
- Check Log Analytics workspace pricing tier is not free (500MB cap)

### Bastion connection fails
- Verify Bastion is in `AzureBastionSubnet` (exact name required)
- Check NSG on Bastion subnet allows inbound 443 from Internet
- Confirm VM is running (not deallocated)

---

---

## Lab Administration - Per-Module Scripts

Every module ships **three admin scripts** (run from DC01) and **one student script** (run from Kali01).

### Script Model

|--------|-----|--------|---------|

> ⚠️ **All admin scripts run from DC01 as Domain Admin.** Never run reset scripts from the management workstation.

---

### Module 01 - SharePoint Webshell (`lab_01_sp_webshell`)

**Before first student (or after new deployment):**
```powershell
# On DC01, as Domain Admin
.\scenarios\module-01-webshell\admin\lab_01_setup.ps1
```
Creates j.chen account, deploys webshell IIS site on SP01, stages toolkit on Kali.

> ⚠️ **IIS setup uses appcmd.exe - do NOT use `Import-Module WebAdministration` via `az run-command`.**
> `az vm run-command` spawns a 32-bit WOW64 PowerShell process. WebAdministration cmdlets in that context
> write to `C:\Windows\SysWOW64\inetsrv\config\applicationHost.config` - **not** the real IIS config at
> `System32\inetsrv\config\`. IIS never reads the WOW64 copy, so the site/pool never appears.
> `lab_01_setup.ps1` calls `sp01-webshell-setup.ps1` which uses `appcmd.exe` directly - this always
> writes to the correct config. If you need to rebuild the webshell site manually, run
> `sp01-webshell-setup.ps1` directly on SP01 (RDP or appcmd via run-command).

**Verify lab is ready:**
```powershell
.\scenarios\module-01-webshell\admin\lab_01_check.ps1
```
Checks DC01, SP01 (:80 + :8080 webshell), j.chen auth, Kali toolkit, clean state.

**Reset between students:**
```powershell
.\scenarios\module-01-webshell\admin\lab_01_reset.ps1
```
Rebuilds SP01 from **`sp01-module01-student` (noWS)** golden image, then re-runs setup. Reset time: ~12 minutes.

**Student preflight (student runs from Kali01):**
```bash
bash /opt/raptor/lab-01/check-lab-01.sh
```
All checks must pass (exit 0) before student proceeds.

---

### Golden Image Reference - SP01

|-------|----------|

> The reset script for Module 01 always rebuilds from `sp01-module01-student`. Never substitute the webShelled image for the student path.

---

### Adding Scripts for New Modules

As new modules are added, follow the same 3+1 pattern:

```
scenarios/
└── module-02-bec/
    ├── admin/
    │   ├── lab_02_setup.ps1
    │   ├── lab_02_check.ps1
    │   └── lab_02_reset.ps1
    └── student/
        └── check-lab-02.sh
```

Each admin set must:
1. Seed required AD accounts / M365 data
2. Stage attack toolkit on Kali from OpenRaptor
3. Rebuild only VMs affected by that module
4. Confirm clean state before handing to student

---

## Recovery Plan - Unrecoverable VMs

Use this plan if a VM crashes and cannot be recovered by a normal restart.

### Recovery Priority

|---|---|---|

---

### SP01 - Rebuild (Normal)

SP01 is designed to be rebuilt. This is the standard student reset flow.

```bash
./scripts/reset-lab.sh
```

If Terraform fails, manual rebuild:
```bash
cd infra
terraform destroy -target module.sp01 -auto-approve
terraform apply -target module.sp01 -auto-approve
```

---

### DC01 - Emergency Rebuild

> ⚠️ Rebuilding DC01 destroys Active Directory. All domain-joined VMs (SP01, Kali) will lose domain membership and need to be rebuilt too.

**Step 1 - Attempt recovery first:**
```bash
# Try a restart
az vm restart -g <YOUR_RESOURCE_GROUP> -n dc01

# Check AD DS service
az vm run-command invoke -g <YOUR_RESOURCE_GROUP> -n dc01 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS,DNS,Netlogon | Select Name,Status"
```

**Step 2 - If unrecoverable, full rebuild:**
```bash
cd infra

# Destroy SP01 first (depends on DC)
terraform destroy -target module.sp01 -auto-approve
terraform destroy -target module.dc01 -auto-approve

# Rebuild DC01 (AD DS setup takes ~20 min)
terraform apply -target module.dc01 -auto-approve

# Wait for DC to be ready, then rebuild SP01
sleep 600
terraform apply -target module.sp01 -auto-approve
```

**Step 3 - Verify AD DS:**
```bash
az vm run-command invoke -g <YOUR_RESOURCE_GROUP> -n dc01 \
  --command-id RunPowerShellScript \
  --scripts "
Get-Service NTDS,DNS,Netlogon | Select Name,Status
(Get-ADDomain).DNSRoot
Get-ADUser -Filter * | Measure-Object | Select Count
"
```

---

### Kali - Emergency Rebuild

Kali is deployed from **Azure Marketplace** (not Community Gallery - Marketplace terms prevent redistribution). Rebuild is safe at any time - no persistent state.

```bash
# Delete the existing Kali VM
az vm delete --resource-group <YOUR_RESOURCE_GROUP> --name kali01 --yes

# Accept Marketplace terms (if not already done)
az vm image terms accept --publisher kali-linux --offer kali --plan kali-2025-4

# Redeploy from Marketplace
az vm create \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --name kali01 \
  --image "kali-linux:kali:kali-2025-4:latest" \
  --size Standard_D2s_v3 \
  --admin-username cirtadmin \
  --admin-password "<YOUR_ADMIN_PASSWORD>" \
  --vnet-name vnet-cirtlab-base \
  --subnet snet-attacker \
  --public-ip-address "" \
  --location <YOUR_REGION>
```

> After rebuild, run `lab_NN_setup.ps1` for the active module - this re-stages the module toolkit from OpenRaptor to `/opt/raptor/lab-NN/`.

**Kali post-deploy setup (automated via `lab_NN_setup.ps1`):**
- Installs: `curl`, `nmap`, `impacket`, `crackmapexec`, `evil-winrm`, `responder`
- Creates `/opt/raptor/` directory structure
- Pulls module scripts from OpenRaptor
- Network pre-configured for lab VNet (`10.10.3.x` subnet)

---

### Full Lab Rebuild (Extreme Case)

> ⚠️ Destroys everything. All student progress is lost. Only use if the resource group is in an unrecoverable state.

```bash
cd infra
terraform destroy -auto-approve
terraform apply -auto-approve
```

Full rebuild: ~45-60 minutes.

---

### Post-Rebuild Checklist

- [ ] DC01 - AD DS, DNS, Netlogon services running
- [ ] SP01 - domain joined, HTTP 200, all SP services running
- [ ] Kali (if rebuilt) - tools present, network connectivity
- [ ] LAW receiving heartbeats from all VMs
- [ ] Run `./scripts/reset-lab.sh` smoke test passes

---

## Security Notes

- No VMs have public IP addresses - all access via Bastion only
- Azure Policy denies public IP creation in `<YOUR_RESOURCE_GROUP>`
- All simulations are **benign** - no real malware, no live exploits
- Do not connect this lab to production systems
- Rotate admin credentials after initial setup

---

## Support

For issues, open a GitHub issue at [<your-org>/OpenRaptor](https://github.com/<your-org>/OpenRaptor/issues).

---

_Last updated: 2026-03-30_
