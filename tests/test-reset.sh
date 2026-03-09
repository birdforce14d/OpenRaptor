#!/usr/bin/env bash
# =============================================================================
# test-reset.sh — Post-reset clean state validation
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run after lab_01_reset.ps1 to confirm SP01 is back to clean state:
#   - Webshell removed
#   - IIS logs rotated / cleared
#   - SharePoint Shared Documents folder clean
#   - SP services healthy
#
# Usage:
#   ADMIN_PASS="CirtApacAdm!n2026" bash tests/test-reset.sh
# =============================================================================

set -uo pipefail

PASS=0; FAIL=0; WARN=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [PASS]${RESET} $1"; ((PASS++)); }
fail() { echo -e "${RED}  [FAIL]${RESET} $1${2:+ — $2}"; ((FAIL++)); }
warn() { echo -e "${YELLOW}  [WARN]${RESET} $1"; ((WARN++)); }
hdr()  { echo -e "\n${YELLOW}[$1]${RESET} $2"; }

SP_IP="${SP_IP:-10.10.3.10}"
SP_HOST="${SP_HOST:-sharepoint.norca.click}"
SP_URL="http://${SP_HOST}"
ADMIN_PASS="${ADMIN_PASS:-CirtApacAdm!n2026}"
STUDENT_PASS="${STUDENT_PASS:-CirtApacStudent2026}"
JCHEN_CREDS="NORCA\\\\j.chen:${STUDENT_PASS}"
SUB="${ARM_SUBSCRIPTION_ID:-68eae5b1-efab-4a2f-a117-c36bbbd72c60}"
RG_CORE="rg-cirtlab-core"
VM_SP01="win-norca-sp01"
CURL_BASE=(curl --connect-timeout 8 --max-time 20 -s --resolve "${SP_HOST}:80:${SP_IP}")

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  OpenRaptor — Post-Reset Clean State Test        ║"
echo "╚══════════════════════════════════════════════════╝"

hdr "1/3" "SP01 Health"
http=$("${CURL_BASE[@]}" -o /dev/null -w "%{http_code}" "$SP_URL" || echo "000")
[[ "$http" =~ ^(200|401|302)$ ]] && ok "SP01 IIS responding (HTTP $http)" \
  || fail "SP01 not responding (HTTP $http)"

hdr "2/3" "Webshell Removed"
shell_code=$("${CURL_BASE[@]}" --ntlm -u "$JCHEN_CREDS" -o /dev/null -w "%{http_code}" \
  "${SP_URL}/Shared%20Documents/help.aspx" || echo "000")
[[ "$shell_code" == "404" || "$shell_code" == "403" ]] \
  && ok "help.aspx not accessible (HTTP $shell_code) — clean ✓" \
  || fail "help.aspx still accessible (HTTP $shell_code) — reset did not remove it"

# Check via az run-command for definitive filesystem confirmation
if command -v az >/dev/null 2>&1; then
  FS_CHECK=$(az vm run-command invoke \
    --resource-group "$RG_CORE" --name "$VM_SP01" --subscription "$SUB" \
    --command-id RunPowerShellScript \
    --scripts "
      \$paths = @(
        'C:\\inetpub\\wwwroot\\wss\\VirtualDirectories\\80\\Shared Documents\\help.aspx',
        'C:\\inetpub\\wwwroot\\wss\\VirtualDirectories\\80\\_layouts\\15\\help.aspx'
      )
      \$found = \$paths | Where-Object { Test-Path \$_ }
      if (\$found) { Write-Output \"FILE_EXISTS:\$found\" } else { Write-Output 'CLEAN' }
    " \
    --query "value[0].message" -o tsv 2>/dev/null || echo "AZ_ERROR")
  [[ "$FS_CHECK" == *"CLEAN"* ]] && ok "Filesystem: help.aspx not found on SP01 ✓" \
    || fail "Filesystem: $FS_CHECK"
fi

hdr "3/3" "IIS Log Rotation"
if command -v az >/dev/null 2>&1; then
  LOG_CHECK=$(az vm run-command invoke \
    --resource-group "$RG_CORE" --name "$VM_SP01" --subscription "$SUB" \
    --command-id RunPowerShellScript \
    --scripts "
      \$logs = Get-ChildItem 'C:\\inetpub\\logs\\LogFiles' -Recurse -Filter '*.log' |
               Sort-Object LastWriteTime -Desc | Select-Object -First 1
      if (-not \$logs) { Write-Output 'NO_LOGS'; exit }
      \$hits = Select-String -Path \$logs.FullName -Pattern 'help\.aspx' -List
      if (\$hits) { Write-Output 'STALE_ENTRIES' } else { Write-Output 'CLEAN' }
    " \
    --query "value[0].message" -o tsv 2>/dev/null || echo "AZ_ERROR")
  [[ "$LOG_CHECK" == *"CLEAN"* || "$LOG_CHECK" == *"NO_LOGS"* ]] \
    && ok "IIS logs clean — no residual help.aspx entries ✓" \
    || fail "IIS logs still contain help.aspx entries — reset_lab.ps1 may not have cleared logs"
else
  warn "az CLI not available — IIS log check skipped"
fi

TOTAL=$((PASS+FAIL+WARN))
echo ""
echo "══════════════════════════════════════════════════"
printf "  Results: ${GREEN}%d PASS${RESET}  ${RED}%d FAIL${RESET}  ${YELLOW}%d WARN${RESET}  / %d total\n" \
  "$PASS" "$FAIL" "$WARN" "$TOTAL"
echo "══════════════════════════════════════════════════"
echo ""
[[ "$FAIL" -eq 0 ]] \
  && echo -e "${GREEN}  ✓ SP01 clean — ready for next student cohort${RESET}\n" \
  || echo -e "${RED}  ✗ Reset incomplete — do not hand to next student${RESET}\n"
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
