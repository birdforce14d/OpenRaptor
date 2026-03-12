# Module 00 — Lab Orientation

## Scenario Brief

> **Welcome to the NORCA Cyber Incident Response Team.**
>
> You've just joined as a Senior Incident Investigator. Before you handle your first case, your CIRT lead wants you to familiarise yourself with the environment — the tools, the log sources, and how things are connected.
>
> *"Take an hour. Poke around. Know where everything is before the pager goes off."*
>
> — CIRT Lead

## Objectives

By the end of this module, you will:
- [ ] Connect to the lab environment via Azure Bastion
- [ ] Navigate the Azure portal and locate key resources
- [ ] Access the Log Analytics Workspace and run a basic query
- [ ] Identify all log sources feeding into the workspace
- [ ] Understand the network topology (subnets, segmentation)
- [ ] Locate the Domain Controller and verify AD DS is running
- [ ] Access the Kali attack box and confirm tools are available
- [ ] Understand the auto-shutdown schedule and TTL policies

## Lab Environment Overview

### Network Architecture

```
┌─────────────────────────────────────────────────────┐
│              VNet: vnet-cirtlab-core                │
│                  10.10.0.0/16                       │
│                                                     │
│  ┌────────────────────┐  ┌────────────────────┐    │
│  │  AzureBastionSubnet│  │  snet-core         │    │
│  │  10.10.0.0/26      │  │  10.10.1.0/24      │    │
│  │                    │  │                    │    │
│  │  • Azure Bastion   │  │  • DC01 10.10.1.10 │    │
│  │    (entry point)   │  │    (norca.click AD)│    │
│  └────────────────────┘  └────────────────────┘    │
│                                                     │
│  ┌────────────────────┐  ┌────────────────────┐    │
│  │  snet-attacker     │  │  snet-target-       │    │
│  │  10.10.2.0/24      │  │  module01           │    │
│  │                    │  │  10.10.3.0/24       │    │
│  │  • Kali01 .10      │  │                    │    │
│  │    (attack box)    │  │  • SP01 10.10.3.10 │    │
│  └────────────────────┘  │    (SharePoint)    │    │
│                           └────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### Key Resources

| Resource | IP | Purpose | Subnet |
|---|---|---|---|
| Azure Bastion | 4.197.157.80 (public) | Sole entry point — no VMs have public IPs | AzureBastionSubnet (10.10.0.0/26) |
| DC01 | 10.10.1.10 | Domain Controller, norca.click AD | snet-core (10.10.1.0/24) |
| Kali01 | 10.10.2.10 | Attack simulation box | snet-attacker (10.10.2.0/24) |
| SP01 (win-norca-sp01) | 10.10.3.10 | SharePoint 2019 — Module 01 target | snet-target-module01 (10.10.3.0/24) |
| Log Analytics Workspace | — | Central telemetry collection | N/A |

### Log Sources

| Source | Log Type | What It Captures |
|---|---|---|
| Entra ID | Sign-in logs, Audit logs | Authentication, user/group changes |
| SharePoint Online | Unified Audit Log | File access, sharing, permissions |
| Windows VMs | Security Event Log | Logon events, process creation, privilege use |
| Azure Activity | Platform logs | Resource changes, policy evaluations |
| NSG Flow Logs | Network logs | Traffic flow between subnets |

## Walkthrough

### Step 1 — Connect via Bastion

1. Open the Azure Portal → navigate to Resource Group `rg-cirtlab-core`
2. Find **DC01** → Click **Connect** → Select **Bastion**
3. Enter credentials:
   - Username: `cirtstudent@norca.click`
   - Password: `CirtApacStudent2026`
   > ℹ️ Students use the domain account for Bastion. Your instructor will confirm when the lab is ready.
4. A browser-based RDP session opens

> 💡 **Why Bastion?** No VMs have public IP addresses. Bastion provides secure, audited access without exposing RDP/SSH to the internet.

### Step 2 — Explore Active Directory

1. On DC01, open **Server Manager** → **Tools** → **Active Directory Users and Computers**
2. Browse the OU structure:
   - `norca.click/Employees` — student accounts (cirtstudent, j.chen) and employee accounts
   - `norca.click/ServiceAccounts` — service accounts (svc-sp-farm, svc-sp-app, svc-sp-search)
   - `norca.click/Computers` — computer objects
   - `norca.click/Domain Controllers` — DC01
3. Note the naming conventions and group memberships

### Step 3 — Access Log Analytics Workspace

1. In Azure Portal → **Log Analytics Workspaces** → `law-cirtlab`
2. Go to **Logs**
3. Run your first query:
   ```kql
   Heartbeat
   | summarize LastHeartbeat = max(TimeGenerated) by Computer
   | order by LastHeartbeat desc
   ```
4. You should see all connected VMs reporting in

### Step 4 — Verify Log Sources

Run these queries to confirm each source is flowing:

**Entra ID Sign-ins:**
```kql
SigninLogs
| take 10
| project TimeGenerated, UserPrincipalName, AppDisplayName, ResultType
```

**Windows Security Events:**
```kql
SecurityEvent
| where EventID == 4624
| take 10
| project TimeGenerated, Computer, Account, LogonType
```

**Azure Activity:**
```kql
AzureActivity
| take 10
| project TimeGenerated, OperationNameValue, Caller, ActivityStatusValue
```

> 🔵 **MDE (Optional):** If Microsoft Defender for Endpoint is licensed and onboarded, verify devices are reporting in the [Microsoft 365 Defender portal](https://security.microsoft.com). Navigate to **Devices** → confirm all lab VMs appear with status **Active**.
> _**MDE (Optional):** If Microsoft Defender for Endpoint is deployed in your environment, your instructor will provide onboarding details separately._

### Step 5 — Network Reconnaissance (from Kali)

1. Connect to **Kali** via Bastion (SSH)
2. Verify connectivity:
   ```bash
   # Can you reach the DC?
   ping -c 2 10.10.1.10 && echo "DC01 OK"

   # Can you reach the SharePoint target?
   ping -c 2 10.10.3.10 && echo "SP01 OK"
   curl -s -o /dev/null -w "SP01 HTTP=%{http_code}\n" http://sharepoint.norca.click

   # Scan the target subnet
   nmap -sn 10.10.3.0/24

   # Check available tools
   which nmap gobuster hashcat john hydra curl
   ```
3. Note which subnets can talk to which — this matters for scenario modules

### Step 6 — Understand Cost Controls

1. In Azure Portal → Resource Group → **Tags**
   - `environment: training`
   - `ttl: 72h` (auto-destroy after 72 hours if tagged)
   - `auto-shutdown: 19:00 UTC`
2. Navigate to any VM → **Auto-shutdown** → verify schedule is set
3. Check **Azure Budgets** → confirm cost alerts are configured

## Self-Assessment

Answer these before moving on:

1. How do you connect to a VM in this lab?
2. What log sources are available in the LAW?
3. Which subnet would a scenario module deploy attack infrastructure to?
4. What happens to VMs at 19:00 UTC?
5. Where would you look for sign-in anomalies?

If you can answer all five, you're ready for Module 01.

## Estimated Time
- 45–60 minutes

## Next Module
→ [Module 01 — SharePoint Webshell Detection](01-sharepoint-webshell.md)

---

> ⚠️ **Note:** This is a training environment. All data is synthetic. Do not connect this environment to production systems.
