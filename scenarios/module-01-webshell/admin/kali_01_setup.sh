#!/bin/bash
# =============================================================================
# Module 01 — Kali Setup (Admin)
# OpenRaptor — OpenRaptor Cyber Range
#
# Run on Kali01 as root/sudo BEFORE handing the lab to a student.
# Downloads and stages the attack toolkit from the public repo.
#
# Usage:
#   sudo ./kali_01_setup.sh
# =============================================================================

set -e

REPO_BASE="https://raw.githubusercontent.com/birdforce14d/OpenRaptor/main/scenarios/module-01-webshell"
DEST="/opt/raptor/module-01"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  Module 01 — Kali Setup (Admin)              ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Create directory structure
echo -e "${YELLOW}[1/4] Creating directory structure...${NC}"
mkdir -p "$DEST/payloads"
echo -e "${GREEN}  [OK] $DEST created${NC}"

# Download attack script
echo -e "${YELLOW}[2/4] Downloading attack script...${NC}"
curl -sL -o "$DEST/attack.sh" "$REPO_BASE/attack.sh"
chmod +x "$DEST/attack.sh"
echo -e "${GREEN}  [OK] attack.sh downloaded${NC}"

# Download student preflight check
echo -e "${YELLOW}[3/4] Downloading student preflight check...${NC}"
curl -sL -o "$DEST/check-lab-01.sh" "$REPO_BASE/student/check-lab-01.sh"
chmod +x "$DEST/check-lab-01.sh"
echo -e "${GREEN}  [OK] check-lab-01.sh downloaded${NC}"

# Download webshell payload
echo -e "${YELLOW}[4/4] Downloading webshell payload...${NC}"
curl -sL -o "$DEST/payloads/help.aspx" "$REPO_BASE/payloads/help.aspx"
echo -e "${GREEN}  [OK] help.aspx downloaded${NC}"

# Set ownership
chown -R kali:kali /opt/raptor

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup complete                              ║${NC}"
echo -e "${GREEN}║                                              ║${NC}"
echo -e "${GREEN}║  Files staged at: /opt/raptor/module-01/     ║${NC}"
echo -e "${GREEN}║  Student can now run: ./check-lab-01.sh      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
