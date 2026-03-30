#!/bin/bash
# =============================================================================
# Module 01 — Lab Environment Preflight Check
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run this BEFORE starting the lab to verify everything is ready.
# Execute from Kali: /opt/raptor/module-01/check-lab-01.sh
#
# Checks:
#   1. Network connectivity to DC01 and SP01
#   2. Domain Controller DNS + LDAP responding
#   3. SharePoint IIS responding
#   4. j.chen can authenticate to SharePoint
#   5. SP01 is in clean state (no webshell present)
#   6. Attack toolkit is staged
#   7. WebDAV endpoint accessible
# =============================================================================

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local hint="$2"
    local code=$3

    if [ "$code" -eq 0 ]; then
        echo -e "  ${GREEN}[✓]${NC} $desc"
        ((PASS++)) || true
    else
        echo -e "  ${RED}[✗]${NC} $desc"
        [ -n "$hint" ] && echo -e "      ${RED}→ $hint${NC}"
        ((FAIL++)) || true
    fi
}

warn() {
    echo -e "  ${YELLOW}[!]${NC} $1"
    ((WARN++)) || true
}

DC01_IP="10.10.1.10"
SP01_IP="10.10.3.10"
SP_URL="http://sharepoint.norca.click"
CREDS="NORCA\\j.chen:CirtApacStudent2026"

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Module 01 — Lab Preflight Check             ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
echo ""

# --- 1. Network connectivity ---
echo -e "${YELLOW}[1/7] Network Connectivity${NC}"

nc -z -w3 "$DC01_IP" 389 > /dev/null 2>&1
check "DC01 ($DC01_IP) is reachable" "Check Azure — is DC01 running?" $?

nc -z -w3 "$SP01_IP" 80 > /dev/null 2>&1
check "SP01 ($SP01_IP) is reachable" "Check Azure — is SP01 running?" $?
echo ""

# --- 2. Domain Controller ---
echo -e "${YELLOW}[2/7] Domain Controller (DC01)${NC}"

nslookup norca.click "$DC01_IP" > /dev/null 2>&1
check "DNS resolution for norca.click via DC01" "DNS not responding — is DC01 running?" $?

timeout 3 bash -c "echo > /dev/tcp/$DC01_IP/389" 2>/dev/null
check "LDAP service (port 389) responding" "LDAP port closed — AD DS may not be running" $?
echo ""

# --- 3. SharePoint Server ---
echo -e "${YELLOW}[3/7] SharePoint Server (SP01)${NC}"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${SP_URL}/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 500 ]; then
    check "SharePoint IIS responding (HTTP $HTTP_CODE)" "" 0
else
    check "SharePoint IIS responding" "Got HTTP $HTTP_CODE — IIS may not be running; check post-deploy log on SP01" 1
fi

timeout 3 bash -c "echo > /dev/tcp/$SP01_IP/3389" 2>/dev/null
check "RDP service (port 3389) on SP01" "RDP not responding — Bastion access may still work" $?
echo ""

# --- 4. AD Account authentication ---
echo -e "${YELLOW}[4/7] Scenario Account (j.chen)${NC}"

AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u "$CREDS" \
  --connect-timeout 5 "${SP_URL}/" 2>/dev/null || echo "000")
if [ "$AUTH_CODE" -ge 200 ] && [ "$AUTH_CODE" -lt 400 ]; then
    check "j.chen can authenticate to SharePoint (HTTP $AUTH_CODE)" "" 0
else
    check "j.chen can authenticate to SharePoint" "HTTP $AUTH_CODE — account may not exist; run lab_01_setup.ps1 on DC01" 1
fi
echo ""

# --- 5. Clean state ---
echo -e "${YELLOW}[5/7] Clean State Verification${NC}"

SHELL_CHECK=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u "$CREDS" \
  --connect-timeout 5 "${SP_URL}/Shared%20Documents/help.aspx" 2>/dev/null || echo "000")
if [ "$SHELL_CHECK" -eq 404 ] || [ "$SHELL_CHECK" -eq 000 ]; then
    check "SP01 is clean (help.aspx not present)" "" 0
else
    check "SP01 is clean (help.aspx not present)" "HTTP $SHELL_CHECK — webshell already present; run lab_01_reset.ps1" 1
fi
echo ""

# --- 6. Attack toolkit ---
echo -e "${YELLOW}[6/7] Attack Toolkit${NC}"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [ -x "$SCRIPT_DIR/attack.sh" ]; then
    check "attack.sh is present and executable" "" 0
else
    check "attack.sh is present and executable" "Missing — run kali_01_setup.sh to deploy toolkit" 1
fi

if [ -f "$SCRIPT_DIR/payloads/help.aspx" ]; then
    check "Webshell payload (help.aspx) is present" "" 0
else
    check "Webshell payload (help.aspx) is present" "Missing — run kali_01_setup.sh to deploy toolkit" 1
fi
echo ""

# --- 7. WebDAV connectivity ---
echo -e "${YELLOW}[7/7] WebDAV Upload Test${NC}"

WEBDAV_CODE=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u "$CREDS" \
  -X OPTIONS --connect-timeout 5 "${SP_URL}/Shared%20Documents/" 2>/dev/null || echo "000")
if [ "$WEBDAV_CODE" -ge 200 ] && [ "$WEBDAV_CODE" -lt 400 ]; then
    check "WebDAV endpoint accessible (HTTP $WEBDAV_CODE)" "" 0
else
    check "WebDAV endpoint accessible" "HTTP $WEBDAV_CODE — WebDAV may be disabled; check SP01 WebDAV settings" 1
fi
echo ""

# --- Summary ---
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}  Result: ALL $TOTAL CHECKS PASSED ✓${NC}"
    echo -e "${GREEN}  Lab environment is ready. Run ./attack.sh to begin.${NC}"
else
    echo -e "${RED}  Result: $FAIL/$TOTAL CHECKS FAILED ✗${NC}"
    echo -e "${RED}  Fix the issues above before starting the lab.${NC}"
    echo -e "${RED}  Contact your instructor if you need help.${NC}"
fi
[ "$WARN" -gt 0 ] && echo -e "${YELLOW}  Warnings: $WARN${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

exit "$FAIL"
