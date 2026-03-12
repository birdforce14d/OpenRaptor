# Module 01 — SharePoint Webshell Detection

## Scenario Brief

> **Classification:** CONFIDENTIAL — Training Exercise Only
>
> **Company:** NORCA
> **Domain:** norca.click
> **Industry:** Financial Services
> **Size:** ~2,500 employees, hybrid cloud environment
>
> ---
>
> **Your Role:** Senior Incident Investigator, Cyber Incident Response Team
>
> **Date:** Monday, 09:14 AM
>
> **Trigger:**
> The IT Service Desk has escalated a ticket to CIRT. A SharePoint site administrator noticed an unfamiliar `.aspx` file in a document library used by the Finance team. The file name doesn't match any known templates or uploads. The administrator tried to open it and received an error page with unusual output.
>
> Meanwhile, the SOC received a medium-severity alert from the monitoring platform flagging an anomalous process execution on the SharePoint server. The overnight SOC analyst marked it as "likely false positive — scheduled task" and closed the alert.
>
> Your CIRT lead has reopened the case and assigned it to you.
>
> **Your Mission:**
> 1. Determine whether the `.aspx` file is a webshell
> 2. Identify how it was uploaded (initial access vector)
> 3. Assess whether the attacker has achieved persistence or lateral movement
> 4. Determine the scope of compromise
> 5. Produce an incident report with findings and recommended containment actions
>
> **What You Have:**
> - RDP access to SharePoint server (`win-norca-sp01`) via Bastion
> - RDP access to domain controller (`dc01`) via Bastion
> - Kali attack machine (`kali01`) via Bastion SSH
> - Windows Event Viewer on all Windows servers
> - IIS log files on the SharePoint server
> - SharePoint ULS logs
> - Azure Log Analytics Workspace (if configured)

## MITRE ATT&CK Mapping

| Technique | ID | Tactic |
|---|---|---|
| Server Software Component: Web Shell | T1505.003 | Persistence |
| Valid Accounts | T1078 | Initial Access |
| Exploitation of Remote Services | T1210 | Lateral Movement |
| Data from Information Repositories: SharePoint | T1213.002 | Collection |

## Difficulty Modes

### 🟢 Guided
Full step-by-step walkthrough with expected outputs at each stage.
_Start here if this is your first time in the lab._

---

#### Phase 0 — Attack Simulation (20 min)

> ⚠️ **Important:** This lab uses a clean SharePoint image. You will simulate the attack first, then switch to investigator mode. In a real incident, this phase has already happened — you're walking in after the fact.

**Step 0.1 — Connect to Kali**

SSH into the Kali attack machine via Azure Bastion:

1. Open the [Azure Portal](https://portal.azure.com)
2. Navigate to **Resource Group** → `rg-cirtlab-core` → `kali01`
3. Click **Connect** → **Bastion** → **SSH**
4. Username: `cirtadmin` / Password: `Norca@2024!`

**Step 0.2 — Run the Preflight Check**

Before starting the attack, verify the lab environment is ready:

```bash
# Verify lab is ready
ping -c 2 10.10.1.10 && echo "DC01 OK" || echo "DC01 UNREACHABLE"
curl -s -o /dev/null -w "SP01 HTTP=%{http_code}\n" http://sharepoint.norca.click
```

> ✅ **Expected:** All checks pass (green). The script verifies:
> - DC01 is up and DNS/LDAP are responding
> - SP01 is up with IIS running
> - The `j.chen` scenario account exists and can authenticate
> - Attack scripts and payloads are in place
> - WebDAV is accessible on SharePoint
>
> If any checks fail, contact your instructor before proceeding. They may need to run the lab setup script on DC01.

**Step 0.3 — Run the Attack Script**

The attack script uploads a webshell to SharePoint and simulates attacker activity. If the payload isn't already on Kali, the script will download it from the student repository automatically.

```bash
# The webshell (cmd.aspx) is pre-seeded by your instructor in IT Admin Uploads.
# Verify it is accessible:
curl -s -o /dev/null -w "%{http_code}" \
  "http://sharepoint.norca.click/IT%20Admin%20Uploads/cmd.aspx?cmd=whoami"
# Expected: 200
```

> 📝 **What the attacker did (pre-seeded):**
> 1. Uploaded `cmd.aspx` to the **IT Admin Uploads** document library via WebDAV using compromised credentials (`NORCA\j.chen`)
> 2. Executed reconnaissance commands through the webshell (`whoami`, `ipconfig`, `net user /domain`)
> 3. The telemetry from these actions is what you will investigate
>
> From Kali you can verify the webshell is live and test it manually using curl.

> ✅ **Expected:** curl returns HTTP 200 and `iis apppool\sharepoint - 80` or similar output. If it fails, check that SP01 is running and reachable from Kali (`ping 10.10.3.10`).

> ⏱️ **Wait 2-3 minutes** after the script completes. This allows Windows Event Logs and IIS logs to flush and be available for your investigation.

**Step 0.4 — Switch Hats**

🎩 You are now the **investigator**. Forget what you just did. From this point, you're a CIRT analyst who's been handed a ticket about a suspicious `.aspx` file. Your job is to find the evidence.

---

#### Phase 1 — Initial Triage with Raw Evidence (25 min)

> 💡 **Approach:** Start with what every defender has — Windows Event Viewer, file system access, and IIS logs. No SIEM required. This is how you investigate when all you have is RDP access to the server.

**Step 1.1 — Connect to SharePoint Server**

RDP into `win-norca-sp01` via Azure Bastion:
1. Azure Portal → `rg-cirtlab-core` → `win-norca-sp01`
2. Click **Connect** → **Bastion** → **RDP**
3. Username: `cirtstudent@norca.click` / Password: `CirtApacStudent2026`

**Step 1.2 — Access the Suspicious File via Browser**

The IT Service Desk ticket says the admin found a strange `.aspx` file and got "unusual output" when opening it. Replicate what they saw:

1. Open **Internet Explorer** on `win-norca-sp01`
2. Navigate to: `http://sharepoint.norca.click/IT%20Admin%20Uploads/cmd.aspx?cmd=whoami`
3. You should see a page with a text box and a "Run" button

> ⚠️ **This is the webshell.** In a real incident, you'd want to be very careful here — interacting with a webshell could alert the attacker or cause further damage. In this lab, it's safe.

Test it — type `whoami` in the text box and click **Run**.

> 🔍 **What you just confirmed:**
> - The `.aspx` file is executable server-side code (not just a document)
> - It accepts user input and executes system commands
> - This is a functional webshell — confirmed T1505.003
>
> **Take a screenshot** of this for your incident report. This is your first piece of evidence.

**Step 1.3 — Find the Suspicious File on Disk**

Open **File Explorer** and navigate to the SharePoint content directory:

```
C:\inetpub\wwwroot\wss\VirtualDirectories\80\
```

Or use PowerShell to search for recently modified `.aspx` files:

```powershell
# Find .aspx files modified in the last 7 days
Get-ChildItem -Path "C:\inetpub" -Recurse -Filter "*.aspx" -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
  Select-Object FullName, LastWriteTime, Length |
  Sort-Object LastWriteTime -Descending
```

> 🔍 **What to look for:**
> - `.aspx` files in unusual locations (document libraries, not `_layouts`)
> - Recently modified files that don't match known SharePoint system files
> - Small files (webshells are typically 1-5 KB)

> ✅ **Expected:** You should find `cmd.aspx` in the **IT Admin Uploads** directory. Note the full path and timestamp.

**Step 1.4 — Examine the File Content**

Open the suspicious file in Notepad:

```powershell
notepad "C:\path\to\cmd.aspx"
```

> 🔍 **Indicators of a webshell:**
> - `System.Diagnostics` import (used to execute processes)
> - `Process` or `ProcessStartInfo` objects
> - `cmd.exe` or `powershell.exe` references
> - Input fields that accept user commands
> - `Request.Form` or `Request.QueryString` reading user input
>
> **Compare against** a normal SharePoint `.aspx` page — legitimate pages reference SharePoint assemblies and web parts, not system process execution.

**Step 1.5 — Check Windows Event Logs**

Open **Event Viewer** (`eventvwr.msc`) and check these logs:

**Security Log — Logon Events (Event ID 4624):**
1. Event Viewer → Windows Logs → Security
2. Filter: Event ID 4624
3. Look for logon events around the time the file was created

> 🔍 **What to look for:**
> - Logon Type 3 (Network) from unexpected IPs — indicates remote authentication
> - The account `j.chen` authenticating to the SharePoint server
> - Logon events at unusual hours

**Security Log — Object Access (Event ID 4663, if auditing enabled):**
- File creation events for the `.aspx` file

**Application Log:**
1. Event Viewer → Windows Logs → Application
2. Look for ASP.NET or IIS errors around the same timeframe
3. A webshell that errors on first access will leave traces here

**Step 1.6 — Check IIS Logs**

IIS logs are your best friend for web-based attacks. They record every HTTP request.

```powershell
# Find IIS log directory
$logDir = "C:\inetpub\logs\LogFiles\W3SVC1"

# Search for requests to the suspicious file
Select-String -Path "$logDir\*.log" -Pattern "cmd.aspx" |
  Select-Object -First 20
```

Or open the log files directly:
```powershell
# Show today's log (IIS logs are named by date: u_exYYMMDD.log)
$today = Get-Date -Format "yyMMdd"
Get-Content "$logDir\u_ex$today.log" | Select-String "cmd.aspx"
```

> 🔍 **IIS log fields to examine:**
>
> ```
> date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip sc-status
> ```
>
> - **cs-method:** `GET` = page load, `POST` = command execution (webshell usage)
> - **cs-uri-stem:** Path to the file being requested
> - **c-ip:** Client IP address — where the requests came from
> - **cs-username:** Authenticated user
> - **sc-status:** HTTP response code (200 = success)
>
> **Key evidence:** Multiple `POST` requests to an `.aspx` file in a document library is a strong webshell indicator. Normal users `GET` documents — they don't `POST` to them.

> ✅ **Expected:** You should see POST requests from the Kali IP (`10.10.2.10`) to `cmd.aspx`. Note the timestamps, source IP, and authenticated user.

---

#### Phase 2 — Identity & Lateral Movement (15 min)

**Step 2.1 — Investigate the Account**

On the **Domain Controller** (`dc01`), check the account used to upload the file:

```powershell
# Check account properties
Get-ADUser -Identity "j.chen" -Properties * |
  Select-Object Name, SamAccountName, LastLogonDate, PasswordLastSet,
    Created, MemberOf, LockedOut, Enabled
```

> 🔍 **What to look for:**
> - When was the password last set? (Recent change could indicate compromise)
> - Is the account locked? (Brute force attempts?)
> - What groups is the account in? (Privileged?)

**Step 2.2 — Check for Logons to Other Servers**

Still on the DC, query Security Event Logs for the compromised account:

```powershell
# Check if j.chen logged into other machines
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    ID = 4624
    StartTime = (Get-Date).AddDays(-7)
} | Where-Object {
    $_.Properties[5].Value -eq 'j.chen'
} | Select-Object TimeCreated,
    @{N='Account';E={$_.Properties[5].Value}},
    @{N='LogonType';E={$_.Properties[8].Value}},
    @{N='SourceIP';E={$_.Properties[18].Value}} |
  Sort-Object TimeCreated -Descending |
  Select-Object -First 20
```

> ✅ **Expected:** If the attacker used `j.chen` to access other machines, you'll see logon events from the Kali IP or from `win-norca-sp01` (indicating lateral movement from the compromised server).

**Step 2.3 — Check for Privilege Escalation Attempts**

```powershell
# Check for group membership changes
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    ID = 4728,4732,4756  # Member added to security-enabled group
    StartTime = (Get-Date).AddDays(-7)
} -ErrorAction SilentlyContinue |
  Select-Object TimeCreated, Message |
  Select-Object -First 10
```

---

#### Phase 3 — Advanced Analysis with Log Analytics (Optional) (15 min)

> 💡 **Context:** If your organisation uses Azure Log Analytics (or any SIEM), you can run queries across multiple data sources simultaneously. This section uses Kusto Query Language (KQL) in the Azure Log Analytics Workspace.
>
> **How to access:**
> 1. Azure Portal → Log Analytics Workspaces → your workspace
> 2. Click **Logs** in the left menu
> 3. Paste queries into the query editor and click **Run**
>
> **Skip this section** if your lab doesn't have Log Analytics configured or if you want to focus on raw evidence investigation.

**Step 3.1 — Correlate IIS Logs in Log Analytics**

If IIS logs are being ingested into your workspace, you can search across time ranges more efficiently:

```kql
W3CIISLog
| where TimeGenerated > ago(7d)
| where csUriStem contains "help.aspx"
| project TimeGenerated, csMethod, csUriStem, cIP, csUserName, scStatus, csUserAgent
| order by TimeGenerated asc
```

> 📝 **What this adds over raw IIS logs:** Faster searching across multiple days, ability to join with other tables (like Security Events), and visualisation.

**Step 3.2 — Correlate Authentication Events**

```kql
SecurityEvent
| where TimeGenerated > ago(7d)
| where EventID == 4624
| where Account contains "j.chen"
| project TimeGenerated, Computer, Account, LogonType, IpAddress
| order by TimeGenerated desc
```

**Step 3.3 — Hunt for Command Execution (Process Creation)**

```kql
SecurityEvent
| where TimeGenerated > ago(7d)
| where Computer == "win-norca-sp01"
| where EventID == 4688  // Process creation
| where ParentProcessName endswith "w3wp.exe"  // IIS worker process
| project TimeGenerated, NewProcessName, CommandLine, Account
| order by TimeGenerated asc
```

> 🔍 **Why this matters:** A webshell runs commands through the IIS worker process (`w3wp.exe`). If you see `cmd.exe` or `powershell.exe` spawned from `w3wp.exe`, that's a confirmed webshell execution.

> 🔵 **MDE (Optional):** If Microsoft Defender for Endpoint is deployed, check the **Device Timeline** for `win-norca-sp01` in the [Microsoft 365 Defender portal](https://security.microsoft.com). Look for:
> - Process tree showing `w3wp.exe` → `cmd.exe`
> - Lateral movement alerts
> - The **Attack Story** view for a correlated kill chain

---

#### Phase 4 — Scope & Reporting (20 min)

**Step 4.1 — Determine Scope**

Based on your investigation, answer:
- [ ] Is the `.aspx` file a webshell? What's your evidence?
- [ ] How was it uploaded? (Compromised credentials via WebDAV)
- [ ] What commands did the attacker run through the webshell?
- [ ] Did the attacker access other systems?
- [ ] What data may have been accessed or exfiltrated?
- [ ] Is the attacker still active?

**Step 4.2 — Write Your Incident Report**

Use this template:

```markdown
# Incident Report — IR-2025-001

## Summary
[One paragraph: what happened, impact, current status]

## Timeline
| Time | Event | Source |
|------|-------|--------|
| ... | ... | ... |

## Findings

### Initial Access
[How did the attacker get in? What account was compromised?]

### Persistence
[What was planted? Full file path? File hash?]

### Execution
[What commands were run through the webshell? Evidence from IIS logs.]

### Lateral Movement
[Did they move to other systems? Evidence from Event Logs.]

### Impact
[What was accessed/compromised?]

## Evidence Summary
| Evidence | Source | Location |
|----------|--------|----------|
| Webshell file | File system | C:\inetpub\...\IT Admin Uploads\cmd.aspx |
| Upload event | IIS logs | C:\inetpub\logs\LogFiles\W3SVC1\u_exYYMMDD.log |
| POST requests | IIS logs | W3SVC1\u_exYYMMDD.log |
| Logon events | Security Event Log | Event ID 4624 |

## Containment Recommendations
1. Delete the webshell file immediately
2. Disable the compromised account (j.chen)
3. Reset j.chen's password
4. Review all j.chen's recent access and actions
5. Scan for additional webshells: `Get-ChildItem -Recurse -Filter "*.aspx" | Select-String "Process\|cmd\.exe\|powershell"`
6. Review IIS logs for other suspicious file uploads

## MITRE ATT&CK Techniques Observed
- T1505.003 — Server Software Component: Web Shell
- T1078 — Valid Accounts
- [Add others if found]
```

> 🏆 **Congratulations!** You've completed Module 01 (Guided). Try it again in Hints or Challenge mode to test yourself without the walkthrough.

---

### 🟡 Hints
You get the objectives and nudges when you're stuck, but no hand-holding.

**Objectives:**
1. Simulate the webshell attack from Kali
2. Find the webshell on the SharePoint server
3. Identify how it was uploaded and by whom
4. Determine what the attacker did with it
5. Check for lateral movement
6. Write an incident report

<details>
<summary>Hint 1 — Verifying the webshell</summary>
The webshell `cmd.aspx` is pre-seeded in the IT Admin Uploads library. From Kali, use curl to hit `http://sharepoint.norca.click/IT%20Admin%20Uploads/cmd.aspx?cmd=whoami` and verify it responds. Then look for the evidence trail on SP01.
</details>

<details>
<summary>Hint 2 — Finding evidence on the server</summary>
Don't jump to KQL. Start with what you can see: File Explorer for the file, Event Viewer for logons, IIS logs for HTTP requests. The evidence is on the box.
</details>

<details>
<summary>Hint 3 — IIS logs are key</summary>
IIS log path: C:\inetpub\logs\LogFiles\W3SVC1\. Search for the filename. POST requests to a document library = webshell activity. Note the source IP and timestamps.
</details>

<details>
<summary>Hint 4 — Process execution evidence</summary>
Check Security Event Log for Event ID 4688 (Process Creation). Look for cmd.exe spawned by w3wp.exe — that's the IIS worker process running your webshell commands.
</details>

<details>
<summary>Hint 5 — Lateral movement</summary>
On the DC, query Security Event Logs for Event ID 4624 with the compromised account. Did it log into machines other than SharePoint?
</details>

---

### 🔴 Challenge

**Briefing:** A suspicious `.aspx` file has been reported on the SharePoint server. You have access to Kali (attacker), SP01 (target), and DC01 (domain controller) via Bastion.

**Tasks:**
1. Simulate a webshell attack from Kali → SP01
2. Investigate using only raw evidence (Event Viewer, IIS logs, file system)
3. Determine the full kill chain
4. Write an incident report with evidence references

**Rules:**
- No hints. No walkthrough.
- You may use Log Analytics if available, but your report must include raw evidence references
- Time target: 45 minutes

---

## Estimated Time
- 🟢 Guided: 90 minutes
- 🟡 Hints: 60 minutes
- 🔴 Challenge: 45 minutes

## Pre-requisites
- Completed Module 00 (Lab Orientation)
- Can connect to lab VMs via Azure Bastion (RDP + SSH)
- Basic familiarity with Windows Event Viewer
- Basic familiarity with IIS log format
- PowerShell basics

## Success Criteria
- [ ] Simulated the webshell attack from Kali
- [ ] Found the webshell file on the SharePoint server
- [ ] Identified the upload method from IIS logs
- [ ] Found process execution evidence in Event Logs
- [ ] Checked for lateral movement
- [ ] Produced incident report with evidence references and MITRE ATT&CK mapping

---

> ⚠️ **Reminder:** This is a benign simulation. No real malware is used. The webshell is a training tool that executes commands — treat it as you would a real webshell in your investigation, but know that it's contained within the lab environment.
