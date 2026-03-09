# OpenRaptor Cyber Range — Handover Sheet

_Complete this form, save as a `.json` file, compress with 7-Zip (AES-256), and send to OD@CIRT.APAC._

> **🔒 Encryption Instructions:**
> 1. Save this file as `handover.json` (fill in your values below)
> 2. Right-click → **7-Zip** → **Add to archive**
> 3. Archive format: **7z** | Encryption method: **AES-256** | ☑️ Encrypt file names
> 4. Password: **provided to you separately by OD@CIRT.APAC via a different channel**
> 5. Send the `.7z` file to the email address provided by OD@CIRT.APAC

---

## 📋 What We Need From You

### Section 1 — Azure Subscription

| Item | Your Value |
|------|-----------|
| **Subscription ID** | |
| **Subscription Name** | |
| **Tenant ID** | |
| **Preferred Region** | _(e.g. `australiaeast`, `eastus`, `uksouth`)_ |

**How to find:**
```bash
az account show --query "{Name:name, SubscriptionId:id, TenantId:tenantId}" -o table
```

---

### Section 2 — Service Principal

Create a service principal for us to deploy into your tenant. We need **two roles**:

```bash
# 1. Create the SP with Contributor role
az ad sp create-for-rbac \
  --name "sp-cirtlab-deploy" \
  --role "Contributor" \
  --scopes "/subscriptions/<YOUR_SUBSCRIPTION_ID>" \
  --sdk-auth

# 2. Add User Access Administrator (for student account creation and RBAC)
az role assignment create \
  --assignee "<SP_CLIENT_ID>" \
  --role "User Access Administrator" \
  --scope "/subscriptions/<YOUR_SUBSCRIPTION_ID>"
```

| Item | Your Value |
|------|-----------|
| **Client ID (Application ID)** | |
| **Client Secret** | |
| **SP Object ID** | |

> ⚠️ Client Secret is shown **once only** when created. Copy it immediately.

---

### Section 3 — VM Quota Confirmation

We deploy 3 VMs. Confirm you have at least **8 vCPUs** available in your chosen region:

```bash
az vm list-usage --location <YOUR_REGION> --output table \
  | grep -E "Standard DSv3|Standard Bsv2|Total Regional"
```

| VM | SKU | vCPUs |
|----|-----|-------|
| DC01 (Domain Controller) | Standard_D2s_v3 | 2 |
| SP01 (SharePoint) | Standard_D4s_v3 | 4 |
| Kali01 (Attacker) | Standard_D2s_v3 | 2 |
| **Total** | | **8** |

- [ ] Quota confirmed: **8+ vCPUs available**

---

### Section 4 — Existing Infrastructure (Avoid List)

Tell us what's already in your subscription so we don't interfere:

| Item | Your Answer |
|------|-----------|
| Existing VNets / IP ranges in use | |
| Resource groups we must NOT touch | |
| Azure Policy restrictions (e.g. allowed regions, VM SKU limits) | |
| Any active VMs we must not interfere with | |

```bash
# List existing VNets
az network vnet list --output table

# List existing resource groups
az group list --output table

# Check Azure Policy
az policy assignment list --output table
```

---

### Section 5 — Lab Configuration

| Item | Your Value |
|------|-----------|
| **Organisation name** _(used in lab scenario)_ | |
| **AD domain** | `norca.click` _(pre-configured, do not change)_ |
| **Admin contact email** _(for handover report)_ | |
| **Number of student accounts** | `1` _(pre-configured)_ |

---

### Section 6 — Microsoft Defender for Endpoint (Optional)

_Skip if you don't use MDE or don't need endpoint telemetry._

| Item | Your Value |
|------|-----------|
| MDE Workspace ID | |
| MDE Workspace Key | |

---

## 📤 JSON Template

Copy, fill in, and save as `handover.json`:

```json
{
  "subscription": {
    "subscriptionId": "",
    "subscriptionName": "",
    "tenantId": "",
    "region": ""
  },
  "servicePrincipal": {
    "clientId": "",
    "clientSecret": "",
    "objectId": ""
  },
  "quotaConfirmed": false,
  "existingInfra": {
    "vnetsInUse": [],
    "resourceGroupsToAvoid": [],
    "policyRestrictions": "",
    "activeVMs": []
  },
  "labConfig": {
    "organisationName": "",
    "adDomain": "norca.click",
    "adminContactEmail": "",
    "studentAccountCount": 1
  },
  "mde": {
    "enabled": false,
    "workspaceId": "",
    "workspaceKey": ""
  }
}
```

---

## 🔐 7-Zip Encryption Steps

1. Save completed `handover.json`
2. Right-click → **7-Zip** → **Add to archive**
3. Settings:
   - Archive format: **7z**
   - Encryption method: **AES-256**
   - ☑️ **Encrypt file names**
   - Password: **provided to you separately by OD@CIRT.APAC**
4. Send the `.7z` file to the email provided by OD@CIRT.APAC

> **⚠️ Never send credentials unencrypted via email, chat, or shared documents.**

---

## 🎓 What We Set Up For You

Once we receive your handover, OD@CIRT.APAC will deploy and configure:

| What | Details |
|------|---------|
| **Domain Controller (DC01)** | Active Directory, DNS, domain user accounts |
| **SharePoint Server (SP01)** | SharePoint 2019 on-prem, domain-joined |
| **Kali Linux (Kali01)** | Attack simulation VM with pre-staged toolkit |
| **Azure Bastion** | Secure browser-based access (no VPN needed) |
| **Log Analytics Workspace** | Centralised logging for all VMs |
| **Student accounts** | Domain users + Entra ID accounts with appropriate access |

### Pre-configured Accounts (created by us):

| Account Type | Username Format | Password |
|-------------|----------------|----------|
| **Domain Admin** | `<DOMAIN>\cirtadmin` | _Provided in handover report_ |
| **Domain Student User** | `<DOMAIN>\j.chen` | _Provided in handover report_ |
| **Entra ID Student** | `student01@<YOUR_DOMAIN>` | _Provided in handover report_ |

> All account credentials will be included in your handover report after deployment.

---

## ✅ Final Checklist

Before sending:

- [ ] Subscription ID, Tenant ID filled in
- [ ] Service principal created with all 3 permission levels
- [ ] VM quota confirmed (8+ vCPUs)
- [ ] Existing infrastructure documented
- [ ] Lab config (org name, domain, email, student count) filled in
- [ ] JSON saved and encrypted with 7-Zip (AES-256)
- [ ] `.7z` file sent to OD@CIRT.APAC email

---

_OpenRaptor Cyber Range — OD@CIRT.APAC_
