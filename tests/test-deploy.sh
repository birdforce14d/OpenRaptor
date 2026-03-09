#!/usr/bin/env bash
# =============================================================================
# test-deploy.sh — Post-Terraform deployment validation
# OpenRaptor Cyber Range — OD@CIRT.APAC
#
# Run from the orchestrator after `terraform apply`.
# Validates Azure resources, network connectivity, and VM health.
# Does NOT require Bastion — uses az CLI + NTLM over private network.
#
# Usage:
#   export ARM_CLIENT_ID="..."
#   export ARM_CLIENT_SECRET="..."
#   export ARM_TENANT_ID="..."
#   export ARM_SUBSCRIPTION_ID="..."
#   bash tests/test-deploy.sh
#
# Exit codes: 0 = all pass, 1 = one or more failures
# =============================================================================

set -uo pipefail

PASS=0; FAIL=0; WARN=0

# ── Colour helpers ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [PASS]${RESET} $1"; ((PASS++)); }
fail() { echo -e "${RED}  [FAIL]${RESET} $1${2:+ — $2}"; ((FAIL++)); }
warn() { echo -e "${YELLOW}  [WARN]${RESET} $1"; ((WARN++)); }
hdr()  { echo -e "\n${YELLOW}[$1]${RESET} $2"; }

# ── Config (override via env) ────────────────────────────────────────────────
SUB="${ARM_SUBSCRIPTION_ID:-68eae5b1-efab-4a2f-a117-c36bbbd72c60}"
RG_CORE="${RG_CORE:-rg-cirtlab-core}"
RG_NET="${RG_NET:-rg-cirtlab-network}"
RG_ATK="${RG_ATK:-rg-cirtlab-attacker}"
SP_IP="${SP_IP:-10.10.3.10}"
DC_IP="${DC_IP:-10.10.1.10}"
KALI_IP="${KALI_IP:-10.10.2.10}"
SP_HOST="${SP_HOST:-sharepoint.norca.click}"
SP_URL="http://${SP_HOST}"
LAW_NAME="${LAW_NAME:-law-cirtlab}"
VNET_NAME="${VNET_NAME:-vnet-cirtlab-base}"
ADMIN_PASS="${ADMIN_PASS:-CirtApacAdm!n2026}"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  OpenRaptor — Post-Deploy Test Suite             ║"
echo "║  Subscription: ${SUB:0:8}...                     ║"
echo "╚══════════════════════════════════════════════════╝"

# ── 1. Azure Resource Groups ─────────────────────────────────────────────────
hdr "1/7" "Resource Groups"
for rg in "$RG_CORE" "$RG_NET" "$RG_ATK"; do
  state=$(az group show --name "$rg" --subscription "$SUB" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
  [[ "$state" == "Succeeded" ]] && ok "RG $rg exists" || fail "RG $rg" "$state"
done

# ── 2. Virtual Machines ──────────────────────────────────────────────────────
hdr "2/7" "Virtual Machines"
declare -A VMS=([dc01]="$RG_CORE" [win-norca-sp01]="$RG_CORE" [kali01]="$RG_ATK")
for vm in "${!VMS[@]}"; do
  rg="${VMS[$vm]}"
  state=$(az vm show -g "$rg" -n "$vm" --subscription "$SUB" \
    --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
  power=$(az vm get-instance-view -g "$rg" -n "$vm" --subscription "$SUB" \
    --query "instanceView.statuses[1].displayStatus" -o tsv 2>/dev/null || echo "unknown")
  [[ "$state" == "Succeeded" ]] && ok "$vm provisioned" || fail "$vm provisioned" "$state"
  [[ "$power" == "VM running" ]] && ok "$vm running" || fail "$vm running" "$power"
done

# ── 3. Networking ────────────────────────────────────────────────────────────
hdr "3/7" "Networking"
vnet=$(az network vnet show -g "$RG_NET" -n "$VNET_NAME" --subscription "$SUB" \
  --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
[[ "$vnet" == "Succeeded" ]] && ok "VNet $VNET_NAME exists" || fail "VNet" "$vnet"

for subnet in snet-core snet-attacker snet-target-module01 AzureBastionSubnet; do
  s=$(az network vnet subnet show -g "$RG_NET" --vnet-name "$VNET_NAME" -n "$subnet" \
    --subscription "$SUB" --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
  [[ "$s" == "Succeeded" ]] && ok "Subnet $subnet" || fail "Subnet $subnet" "$s"
done

# ── 4. Azure Bastion ─────────────────────────────────────────────────────────
hdr "4/7" "Azure Bastion"
bastion=$(az network bastion show -g "$RG_NET" -n "bastion-cirtlab" --subscription "$SUB" \
  --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
[[ "$bastion" == "Succeeded" ]] && ok "Bastion provisioned" || fail "Bastion" "$bastion"

pip=$(az network public-ip show -g "$RG_NET" -n "bastion-cirtlab-pip" --subscription "$SUB" \
  --query "ipAddress" -o tsv 2>/dev/null || echo "")
[[ -n "$pip" ]] && ok "Bastion public IP assigned ($pip)" || fail "Bastion public IP not assigned"

# ── 5. Log Analytics Workspace ───────────────────────────────────────────────
hdr "5/7" "Log Analytics"
law_state=$(az monitor log-analytics workspace show -g "$RG_CORE" -n "$LAW_NAME" \
  --subscription "$SUB" --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
[[ "$law_state" == "Succeeded" ]] && ok "LAW $LAW_NAME exists" || fail "LAW $LAW_NAME" "$law_state"

# Heartbeats — give up to 15min after deploy for first heartbeat
heartbeat=$(az monitor log-analytics query -w \
  "$(az monitor log-analytics workspace show -g $RG_CORE -n $LAW_NAME --subscription $SUB \
     --query customerId -o tsv 2>/dev/null)" \
  --analytics-query "Heartbeat | where TimeGenerated > ago(30m) | summarize count() by Computer" \
  --query "[].Computer" -o tsv 2>/dev/null | wc -l || echo 0)
[[ "$heartbeat" -ge 1 ]] && ok "LAW receiving heartbeats ($heartbeat VMs)" \
  || warn "LAW heartbeats not yet flowing (normal <15min after deploy)"

# ── 6. Private DNS ───────────────────────────────────────────────────────────
hdr "6/7" "Private DNS"
dns=$(az network private-dns zone show -g "$RG_NET" -n "norca.click" --subscription "$SUB" \
  --query "provisioningState" -o tsv 2>/dev/null || echo "NOT_FOUND")
[[ "$dns" == "Succeeded" ]] && ok "DNS zone norca.click" || fail "DNS zone" "$dns"

for rec in sharepoint dc01; do
  r=$(az network private-dns record-set a show -g "$RG_NET" -z "norca.click" -n "$rec" \
    --subscription "$SUB" --query "name" -o tsv 2>/dev/null || echo "")
  [[ -n "$r" ]] && ok "DNS A record: $rec.norca.click" || fail "DNS A record: $rec.norca.click"
done

# ── 7. SharePoint HTTP reachability (from orchestrator if in same VNet) ──────
hdr "7/7" "SharePoint Reachability"
if curl --connect-timeout 8 --max-time 15 -s -o /dev/null -w "%{http_code}" \
   --resolve "${SP_HOST}:80:${SP_IP}" "${SP_URL}" 2>/dev/null | grep -qE "^[2345]"; then
  http_code=$(curl --connect-timeout 8 --max-time 15 -s -o /dev/null -w "%{http_code}" \
    --resolve "${SP_HOST}:80:${SP_IP}" "${SP_URL}" 2>/dev/null)
  [[ "$http_code" =~ ^(200|401|302)$ ]] && ok "SP01 HTTP reachable (${http_code})" \
    || warn "SP01 returned HTTP ${http_code} (may be normal during SharePoint startup)"
else
  warn "SP01 not reachable from orchestrator (expected if orchestrator is outside VNet)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=$((PASS+FAIL+WARN))
echo ""
echo "══════════════════════════════════════════════════"
printf "  Results: ${GREEN}%d PASS${RESET}  ${RED}%d FAIL${RESET}  ${YELLOW}%d WARN${RESET}  / %d total\n" \
  "$PASS" "$FAIL" "$WARN" "$TOTAL"
echo "══════════════════════════════════════════════════"
echo ""
[[ "$FAIL" -eq 0 ]] && echo -e "${GREEN}  ✓ Deployment validated — infrastructure ready${RESET}\n" \
  || echo -e "${RED}  ✗ $FAIL check(s) failed — review above before proceeding${RESET}\n"
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
