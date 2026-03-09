# CIRT Cyber Range — Pre-Deployment Checklist

_Please complete all items below before we begin deployment. This typically takes 15–30 minutes._

---

## How to Use This Checklist

Work through each section in order. For each item, either:
- Run the CLI command shown, or
- Follow the portal steps if you prefer a GUI

Store these values in your own Azure Key Vault. Do not share them externally.

---

## ✅ Section 1 — Subscription Details

We need to know which Azure subscription to deploy into.

**Portal:** Azure Portal → search "Subscriptions" → click your subscription

Collect the following:

| Item | Where to find it | Your value |
|------|-----------------|------------|
| Subscription ID | Subscriptions → Overview → Subscription ID | |
| Tenant ID | Azure Active Directory → Overview → Tenant ID | |
| Subscription name | Subscriptions → Overview → Display name | |

**CLI alternative:**
```bash
az account list --output table
# Note the SubscriptionId and TenantId for your target subscription

az account set --subscription "<YOUR_SUBSCRIPTION_NAME>"
az account show --query "{SubscriptionId:id, TenantId:tenantId, Name:name}"
```

---

## ✅ Section 2 — Service Principal (Deployment Account)

We use a dedicated service principal to deploy. This keeps your personal credentials out of the deployment pipeline.

### Option A — CLI (Recommended, ~2 minutes)

```bash
# Set your subscription first
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Create the service principal with Contributor role
az ad sp create-for-rbac \
  --name "sp-cirtlab-deploy" \
  --role "Contributor" \
  --scopes "/subscriptions/<YOUR_SUBSCRIPTION_ID>" \
  --sdk-auth
```

Copy the entire JSON output — it looks like this:
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

> ⚠️ The `clientSecret` is shown **once only**. Copy it before closing the terminal.

### Option B — Azure Portal (~10 minutes)

1. **Create the app registration:**
   - Azure Active Directory → App registrations → **New registration**
   - Name: `sp-cirtlab-deploy`
   - Supported account types: **Accounts in this organizational directory only**
   - Click **Register**
   - Note the **Application (client) ID** and **Directory (tenant) ID**

2. **Create a client secret:**
   - On the app registration → **Certificates & secrets** → **New client secret**
   - Description: `cirtlab-deploy`
   - Expiry: 6 months
   - Click **Add** — copy the **Value** immediately (shown once only)

3. **Grant Contributor role on subscription:**
   - Azure Portal → **Subscriptions** → your subscription → **Access control (IAM)**
   - **Add role assignment** → Role: **Contributor**
   - Members → **Select members** → search `sp-cirtlab-deploy` → Select
   - Click **Review + assign**

Store these values securely. Do not share Client Secret in plain text — use Azure Key Vault or a secrets manager.

---

## ✅ Section 3 — Region & Quota

### 3a — Choose your region

| Preferred region | Azure region code |
|-----------------|-------------------|
| Australia East | `australiaeast` |
| East US | `eastus` |
| UK South | `uksouth` |
| Southeast Asia | `southeastasia` |

**Your preferred region:** _______________

### 3b — Verify VM quota

We deploy 4 VMs. Check you have available quota:

```bash
# Replace australiaeast with your chosen region
az vm list-usage --location australiaeast --output table \
  | grep -E "Standard DSv3|Standard Bsv2|Total Regional"
```

We need:
| VM SKU | vCPUs | Count | Purpose |
|--------|-------|-------|---------|
| Standard_D2s_v3 | 2 | 2 | DC01 + Kali01 |
| Standard_D4s_v3 | 4 | 1 | SP01 (SharePoint) |
| Standard_B2ms | 2 | 1 | Orchestrator |
| **Total vCPUs** | **10** | | |

> If quota is insufficient: Azure Portal → Subscriptions → Usage + quotas → request increase.

---

## ✅ Section 4 — Existing Infrastructure

Tell us about anything in your subscription we must **not** touch.

| Item | Your answer |
|------|------------|
| Existing VNets / IP ranges in use | |
| Resource groups we must avoid | |
| Azure Policy restrictions (e.g. allowed regions, VM SKU restrictions) | |
| Any active VMs we must not interfere with | |

**CLI — list existing VNets:**
```bash
az network vnet list --output table
```

**CLI — check for Azure Policy assignments:**
```bash
az policy assignment list --output table
```

---

## ✅ Section 5 — Lab Configuration

| Item | Your value |
|------|-----------|
| Organisation name (used in lab scenario, e.g. "NORCA Pty Ltd") | |
| Preferred internal domain (e.g. `corp.local`, `contoso.click`) | |
| Admin contact email (for lab handover report + credentials) | |

---

## ✅ Section 6 — Microsoft Defender for Endpoint (Optional)

Skip this section if you don't use MDE or don't need endpoint telemetry in the lab.

**Portal:** Microsoft 365 Defender → Settings → Endpoints → Device management → Onboarding

| Item | Your value |
|------|-----------|
| MDE Workspace ID | |
| MDE Workspace Key | |

**CLI:**
```bash
# If you have the security CLI configured:
az security workspace-setting list --output table
```

---

## ✅ Section 7 — Confirmation

Once complete, please confirm:

- [ ] Service principal created and credentials collected
- [ ] Subscription ID and Tenant ID noted
- [ ] VM quota verified (10 vCPUs available in chosen region)
- [ ] Existing infra documented (or "none — clean subscription")
- [ ] Lab config values filled in (org name, domain, contact email)
- [ ] All values sent to us via secure channel

---

## What Happens Next

Once we receive your completed checklist:

1. We deploy the full lab (~1 hour)
2. We run automated validation
3. We send you a handover report with:
   - Live lab URL
   - All credentials
   - Student quickstart guide
   - Instructor admin guide
   - Reset procedure

**Questions?** Contact your CIRT team lead.

---

_CIRT Cyber Range — Project Raptor | Last updated: 2026-03-08_

---

## ✅ Section 8 — Golden Images (Community Gallery)

Virtual machines are deployed from pre-built golden images. Before deploying, confirm access to the Community Gallery.

### 8a — Note the Community Gallery Reference

The Raptor team publishes images to an Azure Community Gallery. You will need this reference for your `terraform.tfvars`:

| Variable | Where to find it |
|----------|-----------------|
| `community_gallery_name` | Published in OpenRaptor repo README once live |
| `image_location` | Must match the gallery's published region (e.g. `australiaeast`) |

### 8b — Available Images

| Image Definition | VM | Purpose |
|---|---|---|
| `dc01-base` | DC01 | AD DS + DNS, norca.click domain |
| `sp01-module01-student` | SP01 | Clean SharePoint — noWS (Module 01 default) |
| `sp01-module01` | SP01 | Pre-compromised SharePoint — webShelled (future modules) |
| `kali01-base` | Kali01 | Kali with full attack toolkit |

### 8c — Confirm Image Access

```bash
# Verify you can see the community gallery images
az sig image-definition list-community \
  --location australiaeast \
  --public-gallery-name cirtraptorlab-732fa912-74d1-4049-831b-83781b188c49 \
  --query "[].name" -o table
```

Expected output:
```
dc01-base
kali01-base
sp01-module01
sp01-module01-student
```

- [ ] Community gallery name noted
- [ ] All 4 image definitions visible from your subscription
- [ ] `image_location` matches gallery region

