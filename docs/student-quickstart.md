# Student Quickstart — CIRT Cyber Range

Welcome to the **NORCA CIRT Cyber Range**.

This is a hands-on threat hunting and incident response training environment. You'll investigate realistic attack scenarios, build detection skills, and practice writing incident reports.

---

## Before You Start

You will need:
- ✅ Your lab credentials (provided by your admin)
- ✅ A modern web browser (Chrome or Edge recommended)
- ✅ Access to the [Azure Portal](https://portal.azure.com)

You do **not** need to install anything.

---

## How to Access the Lab

### 1. Sign in to Azure Portal
Go to [portal.azure.com](https://portal.azure.com) and sign in with your provided credentials:
- Username: `student01@norca.click` (e.g. student01@norca.click)
- Password: _(provided by your instructor)_

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
