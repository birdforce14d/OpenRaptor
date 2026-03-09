# Admin Deployment Guide — OpenRaptor Cyber Range

This guide is for administrators deploying the OpenRaptor Cyber Range in a new Azure tenant.

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
- **MDE** — optional, see `{{MDE_LICENSE_DETAILS}}`

---

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
git clone https://github.com/birdforce14d/OpenRaptor.git
cd OpenRaptor
```

---

## Step 3 — Configure Deployment Variables

```bash
cp infra/base/terraform.tfvars.example infra/base/terraform.tfvars
```

Edit `infra/base/terraform.tfvars`:

```hcl
# Azure credentials
tenant_id       = "YOUR_TENANT_ID"
subscription_id = "YOUR_SUBSCRIPTION_ID"
client_id       = "YOUR_CLIENT_ID"
client_secret   = "YOUR_CLIENT_SECRET"   # or use env var TF_VAR_client_secret

# Deployment settings
location        = "australiaeast"        # Change to your preferred region
prefix          = "cirtlab"             # Resource naming prefix
domain_name     = "{{DOMAIN}}"          # Your lab AD domain (e.g. lab.contoso.com)
admin_username  = "cirtadmin"
admin_password  = "<YOUR_ADMIN_PASSWORD>"  # Min 12 chars, upper+lower+number+symbol

# Cost controls
auto_shutdown_time = "1900"             # UTC — VMs shut down daily at this time
ttl_hours          = 72                 # Hours before auto-destroy tag triggers
budget_alert_usd   = 100               # Monthly spend alert threshold

# Optional
deploy_kali        = true
deploy_mde         = false              # Set true if MDE licensed
```

> ⚠️ **Never commit `terraform.tfvars` to Git.** It's in `.gitignore` by default.

---

## Step 4 — Deploy Base Infrastructure

```bash
cd infra/base

# Initialise Terraform (downloads providers, sets up state backend)
terraform init

# Preview what will be deployed
terraform plan -out=tfplan

# Review the plan output carefully, then apply
terraform apply tfplan
```

Deployment takes approximately **15–20 minutes**.

Expected resources created:
- Resource Group `<YOUR_RESOURCE_GROUP>`
- Virtual Network with 4 subnets (management, target, attack, monitoring)
- Azure Bastion + Public IP
- Log Analytics Workspace
- Network Security Groups
- Azure Policy assignments (deny public IPs, restrict SKUs)

---

## Step 5 — Deploy Virtual Machines from Golden Images

VMs are deployed from pre-built golden images in the Azure Compute Gallery. This is faster and more reliable than provisioning from scratch.

### Available Golden Images

| Image Definition | VM | Description |
|---|---|---|
| `dc01-base` | DC01 | Windows Server with AD DS, DNS, norca.click domain pre-configured |
| `sp01-module01-student` | SP01 | SharePoint — **noWS (clean)** — no webshell. Use for Module 01 student path |
| `sp01-module01` | SP01 | SharePoint — **webShelled** — pre-compromised. Reserved for future modules |
| `kali01-base` | Kali | Kali Linux with full attack toolkit pre-installed at `/opt/raptor/` |

> **Source:** Images are published to the Azure Community Gallery. See your deployment `terraform.tfvars` for the gallery reference.

### Deploy from Images

```bash
cd infra/modules/dc01
terraform init && terraform apply -auto-approve

cd ../sp01
# Module 01 uses the noWS image — configured in sp01/main.tf
terraform init && terraform apply -auto-approve

cd ../kali01
terraform init && terraform apply -auto-approve
```

> ⏳ VM provisioning from golden images takes **5–10 minutes** per VM (significantly faster than full provisioning).

### Configure Community Gallery Reference

In `infra/base/terraform.tfvars`, set the gallery reference:

```hcl
# Community Gallery — source of golden images
community_gallery_name = "cirtraptorlab-732fa912-74d1-4049-831b-83781b188c49"   # from OpenRaptor README
image_location         = "australiaeast"               # must match gallery region
```

> 📌 The community gallery name will be published in the OpenRaptor repo README once images are live.

---

## Step 6 — Post-Deploy Verification

Run the smoke test script:

```bash
cd ../../..
bash scripts/smoke-test.sh
```

Expected output:
```
[OK] VNet deployed
[OK] Bastion reachable
[OK] DC01 running — norca.click domain active
[OK] SP01 running — domain joined — HTTP 200
[OK] Log Analytics receiving heartbeats
[OK] Entra ID sign-in logs flowing
[OK] SharePoint audit logs flowing
```

If any check fails, see **Troubleshooting** below.

---

## Step 7 — Configure Student Access

### Create Student Accounts in Entra ID

```bash
# Create a student user
az ad user create \
  --display-name "Student 01" \
  --user-principal-name "student01@{{DOMAIN}}" \
  --password "<YOUR_STUDENT_PASSWORD>" \
  --force-change-password-next-sign-in false
```

### Assign Log Analytics Reader Role

```bash
az role assignment create \
  --assignee "student01@{{DOMAIN}}" \
  --role "Log Analytics Reader" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/<YOUR_RESOURCE_GROUP>
```

### Share Bastion Access URL

Students connect via Bastion:
1. Azure Portal → Resource Group `<YOUR_RESOURCE_GROUP>`
2. Select target VM → **Connect** → **Bastion**
3. Use provided credentials

> 💡 You can also create a custom Azure Portal dashboard with direct links to each VM and the Log Analytics Workspace.

---

## Step 8 — Launch a Scenario Module

```bash
# Example: Deploy the SharePoint webshell scenario
cd infra/modules/sp-webshell
terraform init && terraform apply -auto-approve
```

Each module auto-tags resources with TTL for cleanup:
```
ttl = "72h"
module = "sp-webshell"
```

---

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
# Destroy scenario modules first
cd infra/modules/sp-webshell && terraform destroy -auto-approve

# Then destroy base infra
cd infra/base && terraform destroy -auto-approve
```

---

## Troubleshooting

### SP01 SharePoint not responding after reboot
```powershell
# Run via Bastion on SP01
Import-Module WebAdministration
Set-ItemProperty "IIS:\AppPools\SharePoint - 80" -Name processModel.userName -Value "DOMAIN\cirtadmin"
Set-ItemProperty "IIS:\AppPools\SharePoint - 80" -Name processModel.password -Value "YOUR_PASSWORD"
Set-ItemProperty "IIS:\AppPools\SharePoint - 80" -Name processModel.identityType -Value 3
Start-Service SPTimerV4, SPAdminV4, AppFabricCachingService, W3SVC
Start-WebAppPool "SharePoint - 80"
```

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
Creates j.chen account, stages toolkit on Kali from OpenRaptor.

**Verify lab is ready:**
```powershell
.\scenarios\module-01-webshell\admin\lab_01_check.ps1
```
Checks DC01, SP01, j.chen auth, Kali toolkit, clean state.

**Reset between students:**
```powershell
.\scenarios\module-01-webshell\admin\lab_01_reset.ps1
```
Rebuilds SP01 from **`sp01-module01-student` (noWS)** golden image. Reset time: ~10 minutes.

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

Kali is built from the `kali01-base` golden image which includes the full attack toolkit pre-installed at `/opt/raptor/`. Rebuild is safe at any time — no persistent state.

```bash
cd infra
terraform destroy -target module.kali01 -auto-approve
terraform apply -target module.kali01 -auto-approve
```

> After rebuild, run `lab_NN_setup.ps1` for the active module — this re-stages the module-specific toolkit from OpenRaptor to `/opt/raptor/lab-NN/`.

**What the Kali golden image includes:**
- Kali Linux (latest stable)
- Pre-installed: `curl`, `nmap`, `impacket`, `crackmapexec`, `evil-winrm`, `responder`
- `/opt/raptor/` directory structure (module scripts pulled at setup time)
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

For issues, open a GitHub issue at `<your-github-org>/OpenRaptor`.

---

_Last updated: 2026-03-09_
