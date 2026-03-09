#!/bin/bash
# =============================================================================
# Module 01 — Lab Environment Preflight Check
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run this BEFORE starting the lab to verify everything is ready.
# Execute from Kali: /opt/raptor/module-01/preflight.sh
#
# Checks:
#   1. DC01 is reachable and responding
#   2. SP01 is reachable and domain-joined
#   3. SharePoint IIS is responding
#   4. j.chen AD account exists
#   5. Attack scripts are in place
#   6. WebDAV connectivity to SharePoint
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
    local result="$2"
    local code=$3

    if [ $code -eq 0 ]; then
        echo -e "  ${GREEN}[✓]${NC} $desc"
        ((PASS++))
    else
        echo -e "  ${RED}[✗]${NC} $desc"
        [ -n "$result" ] && echo -e "      ${RED}→ $result${NC}"
        ((FAIL++))
    fi
}

warn() {
    local desc="$1"
    echo -e "  ${YELLOW}[!]${NC} $desc"
    ((WARN++))
}

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Module 01 — Lab Preflight Check             ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
echo ""

# --- 1. Network connectivity ---
echo -e "${YELLOW}[1/6] Network Connectivity${NC}"

DC01_IP="10.10.1.10"
SP01_IP="10.10.2.10"

ping -c 1 -W 3 "$DC01_IP" > /dev/null 2>&1
check "DC01 ($DC01_IP) is reachable" "" $?

ping -c 1 -W 3 "$SP01_IP" > /dev/null 2>&1
check "SP01 ($SP01_IP) is reachable" "" $?

echo ""

# --- 2. Domain Controller ---
echo -e "${YELLOW}[2/6] Domain Controller (DC01)${NC}"

# Check DNS resolution via DC01
nslookup norca.click "$DC01_IP" > /dev/null 2>&1
check "DNS resolution for norca.click via DC01" "DNS not responding — is DC01 running?" $?

# Check LDAP port
timeout 3 bash -c "echo > /dev/tcp/$DC01_IP/389" 2>/dev/null
check "LDAP service (port 389) responding" "LDAP port closed — AD may not be running" $?

echo ""

# --- 3. SharePoint Server ---
echo -e "${YELLOW}[3/6] SharePoint Server (SP01)${NC}"

# Check IIS
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://sharepoint.norca.click/" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 500 ]; then
    check "SharePoint IIS responding (HTTP $HTTP_CODE)" "" 0
else
    check "SharePoint IIS responding" "Got HTTP $HTTP_CODE — IIS may not be running" 1
fi

# Check RDP port (for later investigation phase)
timeout 3 bash -c "echo > /dev/tcp/$SP01_IP/3389" 2>/dev/null
check "RDP service (port 3389) on SP01" "RDP not available — Bastion access may still work" $?

echo ""

# --- 4. AD Account ---
echo -e "${YELLOW}[4/6] Scenario Account (j.chen)${NC}"

# Test authentication with j.chen via NTLM
AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u 'NORCA\j.chen:<YOUR_STUDENT_PASSWORD>' \
  --connect-timeout 5 "http://sharepoint.norca.click/" 2>/dev/null || echo "000")
if [ "$AUTH_CODE" -ge 200 ] && [ "$AUTH_CODE" -lt 400 ]; then
    check "j.chen can authenticate to SharePoint (HTTP $AUTH_CODE)" "" 0
else
    check "j.chen can authenticate to SharePoint" "HTTP $AUTH_CODE — account may not exist. Ask instructor to run seed-domain.ps1 on DC01" 1
fi

echo ""

# --- 5. Clean state + Attack toolkit ---
echo -e "${YELLOW}[5/7] Clean State Verification${NC}"

# Verify webshell is NOT already present (confirms clean/noWS image)
SHELL_CHECK=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u 'NORCA\j.chen:<YOUR_STUDENT_PASSWORD>' \
  --connect-timeout 5 "http://sharepoint.norca.click/Shared%20Documents/help.aspx" 2>/dev/null || echo "000")
if [ "$SHELL_CHECK" -eq 404 ] || [ "$SHELL_CHECK" -eq 000 ]; then
    check "SP01 is clean (help.aspx not present — expected)" "" 0
else
    check "SP01 is clean (help.aspx not present)" "HTTP $SHELL_CHECK — webshell already exists. Lab may need reset." 1
fi

echo ""

echo -e "${YELLOW}[6/7] Attack Toolkit${NC}"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

if [ -x "$SCRIPT_DIR/attack.sh" ]; then
    check "attack.sh is present and executable" "" 0
else
    check "attack.sh is present and executable" "Missing — toolkit not deployed to Kali" 1
fi

if [ -f "$SCRIPT_DIR/payloads/help.aspx" ]; then
    check "Webshell payload (help.aspx) is present" "" 0
else
    check "Webshell payload (help.aspx) is present" "Missing — run: wget -O payloads/help.aspx <REPO_URL>" 1
fi

echo ""

# --- 6. WebDAV connectivity ---
echo -e "${YELLOW}[7/7] WebDAV Upload Test${NC}"

# Test OPTIONS request to check WebDAV support
WEBDAV_CODE=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u 'NORCA\j.chen:<YOUR_STUDENT_PASSWORD>' \
  -X OPTIONS --connect-timeout 5 "http://sharepoint.norca.click/Shared%20Documents/" 2>/dev/null || echo "000")
if [ "$WEBDAV_CODE" -ge 200 ] && [ "$WEBDAV_CODE" -lt 400 ]; then
    check "WebDAV endpoint accessible (HTTP $WEBDAV_CODE)" "" 0
else
    check "WebDAV endpoint accessible" "HTTP $WEBDAV_CODE — WebDAV may be disabled on SharePoint" 1
fi

echo ""

# --- Summary ---
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}  Result: ALL $TOTAL CHECKS PASSED ✓${NC}"
    echo -e "${GREEN}  Lab environment is ready. Proceed to attack simulation.${NC}"
else
    echo -e "${RED}  Result: $FAIL/$TOTAL CHECKS FAILED ✗${NC}"
    echo -e "${RED}  Fix the issues above before starting the lab.${NC}"
    echo -e "${RED}  Contact your instructor if you need help.${NC}"
fi
[ $WARN -gt 0 ] && echo -e "${YELLOW}  Warnings: $WARN${NC}"
echo -e "${YELLOW}══════════════════════════════════════════════${NC}"
echo ""

exit $FAIL
