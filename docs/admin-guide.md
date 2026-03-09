# Admin Deployment Guide — CIRT Cyber Range

This guide is for administrators deploying the CIRT Cyber Range in a new Azure tenant.

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
git clone https://github.com/<YOUR_ORG>/OpenRaptor.git
cd cirt-cyber-range
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

## Step 5 — Deploy Virtual Machines

### DC01 and SP01 (Terraform)

```bash
cd ../modules/dc01
terraform init && terraform apply -auto-approve

cd ../sp01
terraform init && terraform apply -auto-approve
```

### Kali01 (Azure Marketplace)

Deploy Kali Linux from the Azure Marketplace:

```bash
# Accept the Marketplace terms for Kali Linux
az vm image terms accept --publisher kali-linux --offer kali --plan kali-2025-1 --output none

# Deploy Kali VM
az vm create \
  --resource-group <RESOURCE_GROUP> \
  --name kali01 \
  --image kali-linux:kali:kali-2025-1:latest \
  --size Standard_D2s_v3 \
  --vnet-name <VNET_NAME> \
  --subnet snet-attacker \
  --private-ip-address 10.10.3.10 \
  --public-ip-address "" \
  --admin-username kali \
  --admin-password "<STUDENT_PASSWORD>" \
  --nsg "" \
  --no-wait
```

> 📝 **Note:** If the Kali plan above is unavailable in your region, list available plans:
> ```bash
> az vm image list --publisher kali-linux --all --output table
> ```

Once Kali01 is running, SSH in via Bastion and run the setup script to stage the attack toolkit:

```bash
# On Kali01 (via Bastion SSH)
curl -sL https://raw.githubusercontent.com/birdforce14d/OpenRaptor/main/scenarios/module-01-webshell/admin/kali_01_setup.sh | sudo bash
```

This downloads and stages all Module 01 files to `/opt/raptor/module-01/` — the attack script, student preflight check, and webshell payload.

> ✅ **Verify:** `ls /opt/raptor/module-01/` should show `attack.sh`, `check-lab-01.sh`, and `payloads/help.aspx`.

> ⏳ VM provisioning takes **20–30 minutes** per VM including extensions and domain setup.

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

## Lab Reset — Between Students

Reset scripts are run from **DC01**. Each module has its own reset script.

### Module 01 — SharePoint Webshell

```powershell
# On DC01, run as Domain Admin
\\dc01\scripts\lab_01_sp_webshell.ps1
```

**What the script does:**
1. Rebuilds SP01 from the clean golden image (`sp01-module01/1.0.0`)
2. Re-runs `seed-domain.ps1` to ensure `j.chen` account exists
3. Deploys attack toolkit to Kali at `/opt/raptor/module-01/`
4. Runs a smoke test (SP01 reachable, IIS responding, j.chen can authenticate)

**Reset time:** ~15 minutes.

### Adding New Module Reset Scripts

As new modules are added, create corresponding scripts:
- `lab_02_bec.ps1` — Module 02 (Business Email Compromise)
- `lab_03_aitm.ps1` — Module 03 (AiTM Credential Theft)
- etc.

Each script should:
1. Rebuild only the VMs affected by that module
2. Seed any required AD accounts or artifacts
3. Deploy attack tooling to Kali
4. Run a smoke test before declaring the lab ready

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

Kali has no persistent state. Rebuild is safe at any time.

```bash
cd infra
terraform destroy -target module.kali01 -auto-approve
terraform apply -target module.kali01 -auto-approve
```

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

For issues, open a GitHub issue at `<YOUR_ORG>/OpenRaptor`.

---

_Last updated: 2026-03-08_
