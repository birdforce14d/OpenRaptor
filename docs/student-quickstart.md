# Student Quickstart — OpenRaptor Cyber Range

Welcome to the **NORCA OpenRaptor Cyber Range**.

This is a hands-on threat hunting and incident response training environment. You'll investigate realistic attack scenarios, build detection skills, and practice writing incident reports.

---

## Before You Start

You will need:
- ✅ Your lab credentials (provided by your admin)
- ✅ A modern web browser (Chrome or Edge recommended)
- ✅ Access to Azure Bastion links (provided by your instructor)

You do **not** need to install anything.

---

## How to Access the Lab

### 1. Connect via Azure Bastion
Your instructor will provide a direct Bastion link to each lab VM. Access is browser-based — no VPN or Azure Portal login required.

> ⚠️ **Do not attempt to sign in to the Azure Portal with your lab credentials.** The `cirtstudent` account is an on-premises Active Directory account and cannot authenticate to Azure AD / Entra ID.

Connect to each VM using:
- **Username:** `NORCA\\cirtstudent` (or just `cirtstudent` in the Bastion username field)
- **Password:** provided by your instructor

### 2. Navigate to the Lab Environment
1. In the Azure Portal search bar, type **Resource Groups**
2. Select `rg-cirtlab-core`
3. You'll see the lab resources

### 3. Connect to a VM via Bastion
1. Click on a VM (e.g. `dc01` or `win-norca-sp01`)
2. Click **Connect** → **Bastion**
3. Enter the VM credentials provided by your instructor
4. A browser-based desktop session opens — no VPN, no RDP client needed

### 4. Access Log Analytics
1. In the Azure Portal, search for **Log Analytics Workspaces**
2. Select `law-cirtlab`
3. Click **Logs** to start querying

---

## Lab Rules

- 🚫 Do not attempt to escalate privileges beyond what's needed for the scenario
- 🚫 Do not modify infrastructure (VMs, networks, policies)
- 🚫 Do not connect the lab to any external systems
- ✅ Do document your findings as you go
- ✅ Do ask questions — this is a learning environment

---

## Training Modules

Work through these in order:

| Module | Title | Level | Time |
|--------|-------|-------|------|
| 00 | [Lab Orientation](lab-guide/00-orientation.md) | 🟢 All | 45–60 min |
| 01 | [SharePoint Webshell Detection](lab-guide/01-sharepoint-webshell.md) | 🟡 Intermediate | 45–90 min |
| 02 | BEC Investigation _(coming soon)_ | 🟡 Intermediate | TBD |
| 03 | AiTM Credential Theft Defense _(coming soon)_ | 🔴 Advanced | TBD |
| 04 | Cross-Cloud Federation Abuse _(coming soon)_ | 🔴 Advanced | TBD |
| 05 | Capstone — Full IR Scenario _(coming soon)_ | 🏆 Expert | TBD |

### Difficulty Modes
Each module has three modes — choose what suits your experience level:
- 🟢 **Guided** — step-by-step with expected outputs
- 🟡 **Hints** — objectives + nudges when stuck
- 🔴 **Challenge** — objectives only, no help

---

## Lab Environment — Key Endpoints

For reference during your investigation exercises:

| System | Address | Purpose |
|--------|---------|---------|
| SharePoint | `http://sharepoint.norca.click` (port 80) | NORCA intranet — primary investigation target |
| ShellSite | `http://10.10.3.10:8080` (port 8080) | Module 01 scenario artefact — attacker persistence mechanism |
| DC01 | `10.10.1.10` | Domain controller — authentication, AD investigation |
| Kali01 | `10.10.2.10` | Attack workstation — attack simulation |

> ⚠️ **ShellSite is a scenario artefact.** It is an intentionally deployed webshell running as `NT AUTHORITY\SYSTEM`. Do not be alarmed by it — it's part of the lab. Your job in Module 01 is to *find* it as part of your investigation.

---

## Validating Your Lab Environment (Before You Start)

Before beginning any module, confirm the lab is ready. Run these from the SharePoint server (`win-norca-sp01`) or from your analyst workstation.

### Quick validation checklist

```powershell
# 1. SharePoint intranet is up
Invoke-WebRequest -Uri "http://sharepoint.norca.click" -UseBasicParsing | Select StatusCode
# Expected: 200 or 401

# 2. Module 01 scenario endpoint is reachable (run from SP01)
Test-NetConnection -ComputerName localhost -Port 8080
# Expected: TcpTestSucceeded : True

# 3. Functional test (run from SP01)
curl.exe "http://localhost:8080/cmd.aspx?cmd=whoami"
# Expected: nt authority\system
```

If all three pass — your lab is ready. If not, contact your instructor before proceeding.

### Known errors and quick fixes

These are the errors students most commonly see before lab setup is complete. **Do not attempt to fix these yourself** — contact your instructor and quote the error code.

| What you see | What it means | Who fixes it |
|---|---|---|
| `curl: (7) Failed to connect to localhost port 8080` | ShellSite not yet deployed or site stopped | Instructor runs `sp01-webshell-setup.ps1` |
| `TcpTestSucceeded : False` on port 8080 | Same as above — no listener on 8080 | Instructor |
| **HTTP 500.19** — "cannot read configuration file" | `web.config` missing in site root | Instructor recreates `web.config` |
| SharePoint returns 503 | SharePoint app pool stopped | Instructor restarts SP01 or app pools |
| `Unable to connect to remote server` on port 80 | SharePoint down or IIS stopped | Instructor |

> 💡 The most common setup issue is the Module 01 port 8080 endpoint. If `Test-NetConnection localhost -Port 8080` returns `False`, the lab is not ready. Tell your instructor.

---

## Tips for Success

**Take notes as you go.** Use the incident report template in each module. The ability to document findings clearly is as important as finding them.

**Don't skip the orientation.** Module 00 teaches you where everything is. You'll move faster in later modules if you've done it first.

**Use the three-tiered approach.** If you're stuck in Challenge mode, switch to Hints. No shame — the point is to learn.

**Time yourself.** The estimated times are benchmarks. Beating them in Challenge mode is a good sign you're ready for harder scenarios.

---

## Getting Help

- Ask your instructor
- Re-read the scenario brief — the clues are usually there
- Use the hints (Hints mode only)

---

_Good luck. Find the threat. Write the report. 🔍_
