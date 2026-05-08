#!/bin/bash
# Generate SVG + Markdown network diagram for the tunnelless_cloudwan project.
# Queries live AWS state in both regions and Cloud WAN; falls back to tfvars CIDRs
# when infrastructure is not yet deployed.
#
# Usage:
#   ./generate_network_diagram.sh               # Full regeneration
#   ./generate_network_diagram.sh --update-fgt  # Refresh FortiGate IPs in existing MD only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TFVARS_FILE="${PROJECT_DIR}/terraform.tfvars"
SVG_FILE="${PROJECT_DIR}/network_diagram.svg"
MD_FILE="${PROJECT_DIR}/network_diagram.md"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'
print_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }
print_pass()    { echo -e "${GREEN}[PASS]${NC} $1"; }
print_fail()    { echo -e "${RED}[FAIL]${NC} $1"; }
print_info()    { echo -e "${YELLOW}[INFO]${NC} $1"; }

# ── Argument parsing ────────────────────────────────────────────────────────
UPDATE_FGT_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --update-fgt) UPDATE_FGT_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--update-fgt]"
            echo "  --update-fgt  Refresh FortiGate IPs in existing network_diagram.md only"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Prerequisites ───────────────────────────────────────────────────────────
if [[ ! -f "$TFVARS_FILE" ]]; then
    print_fail "terraform.tfvars not found: $TFVARS_FILE"
    print_info "Copy terraform.tfvars.example and fill in values, then re-run."
    exit 1
fi
for cmd in aws jq; do
    if ! command -v "$cmd" &>/dev/null; then
        print_fail "$cmd not found — install it and re-run"
        exit 1
    fi
done

# ── tfvars reader ───────────────────────────────────────────────────────────
get_tfvar() {
    local key="$1" file="$2"
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null \
        | head -1 | sed 's/.*=[[:space:]]*//' | sed 's/[[:space:]]*#.*//' \
        | tr -d '"' | tr -d "'" | tr -d '[:space:]'
}

# ── Read configuration ──────────────────────────────────────────────────────
print_section "READING CONFIGURATION"

CP=$(get_tfvar "cp" "$TFVARS_FILE")
ENV=$(get_tfvar "env" "$TFVARS_FILE")
PREFIX="${CP}-${ENV}"
FGT_ASN=$(get_tfvar "fgt_asn" "$TFVARS_FILE")
CNE_ASN_EAST=$(get_tfvar "cne_asn" "$TFVARS_FILE")
CNE_ASN_WEST=$((CNE_ASN_EAST + 1))

# CIDRs from tfvars — used as plan-time values / fallbacks
EAST_INSP_VPC_CIDR=$(get_tfvar "east_inspection_vpc_cidr"           "$TFVARS_FILE")
EAST_PUB_AZ1=$(get_tfvar      "east_inspection_public_az1_cidr"    "$TFVARS_FILE")
EAST_PUB_AZ2=$(get_tfvar      "east_inspection_public_az2_cidr"    "$TFVARS_FILE")
EAST_PRIV_AZ1=$(get_tfvar     "east_inspection_private_az1_cidr"   "$TFVARS_FILE")
EAST_PRIV_AZ2=$(get_tfvar     "east_inspection_private_az2_cidr"   "$TFVARS_FILE")
EAST_HA_AZ1=$(get_tfvar       "east_inspection_ha_sync_az1_cidr"   "$TFVARS_FILE")
EAST_HA_AZ2=$(get_tfvar       "east_inspection_ha_sync_az2_cidr"   "$TFVARS_FILE")
EAST_SPOKE_A_CIDR=$(get_tfvar "east_spoke_a_vpc_cidr"              "$TFVARS_FILE")
EAST_SPOKE_B_CIDR=$(get_tfvar "east_spoke_b_vpc_cidr"              "$TFVARS_FILE")

WEST_INSP_VPC_CIDR=$(get_tfvar "west_inspection_vpc_cidr"           "$TFVARS_FILE")
WEST_PUB_AZ1=$(get_tfvar      "west_inspection_public_az1_cidr"    "$TFVARS_FILE")
WEST_PUB_AZ2=$(get_tfvar      "west_inspection_public_az2_cidr"    "$TFVARS_FILE")
WEST_PRIV_AZ1=$(get_tfvar     "west_inspection_private_az1_cidr"   "$TFVARS_FILE")
WEST_PRIV_AZ2=$(get_tfvar     "west_inspection_private_az2_cidr"   "$TFVARS_FILE")
WEST_HA_AZ1=$(get_tfvar       "west_inspection_ha_sync_az1_cidr"   "$TFVARS_FILE")
WEST_HA_AZ2=$(get_tfvar       "west_inspection_ha_sync_az2_cidr"   "$TFVARS_FILE")
WEST_SPOKE_A_CIDR=$(get_tfvar "west_spoke_a_vpc_cidr"              "$TFVARS_FILE")
WEST_SPOKE_B_CIDR=$(get_tfvar "west_spoke_b_vpc_cidr"              "$TFVARS_FILE")

# BGP peer IPs: cidrhost(private_az_cidr, 1) — first IP of each private subnet
# For /24 subnets: just replace last octet with 1
cidrhost1() { local net="${1%/*}"; echo "${net%.*}.1"; }
fgt_dot10() { local net="${1%/*}"; echo "${net%.*}.10"; }

EAST_CNE_BGP_PRI=$(cidrhost1   "$EAST_PRIV_AZ1")
EAST_CNE_BGP_SEC=$(cidrhost1   "$EAST_PRIV_AZ2")
WEST_CNE_BGP_PRI=$(cidrhost1   "$WEST_PRIV_AZ1")
WEST_CNE_BGP_SEC=$(cidrhost1   "$WEST_PRIV_AZ2")
EAST_FGT_PRI_P2=$(fgt_dot10    "$EAST_PRIV_AZ1")
EAST_FGT_SEC_P2=$(fgt_dot10    "$EAST_PRIV_AZ2")
WEST_FGT_PRI_P2=$(fgt_dot10    "$WEST_PRIV_AZ1")
WEST_FGT_SEC_P2=$(fgt_dot10    "$WEST_PRIV_AZ2")

print_info "Prefix: $PREFIX | FGT ASN: $FGT_ASN | East CNE ASN: $CNE_ASN_EAST | West CNE ASN: $CNE_ASN_WEST"

# ── AWS query helpers ───────────────────────────────────────────────────────
_aws() { aws --region "$1" "${@:2}" 2>/dev/null || echo ""; }

none_to_empty() { [[ "$1" == "None" ]] && echo "" || echo "$1"; }

get_vpc_id() {
    local result
    result=$(aws ec2 describe-vpcs --region "$1" \
        --filters "Name=tag:Name,Values=$2" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    none_to_empty "$result"
}

get_instance_attr() {
    local result
    result=$(aws ec2 describe-instances --region "$1" \
        --filters "Name=tag:Name,Values=$2" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].$3" --output text 2>/dev/null)
    none_to_empty "$result"
}

get_eip() {
    local result
    result=$(aws ec2 describe-addresses --region "$1" \
        --filters "Name=tag:Name,Values=$2" \
        --query 'Addresses[0].PublicIp' --output text 2>/dev/null)
    none_to_empty "$result"
}

# ── --update-fgt mode: refresh FortiGate rows in existing MD ───────────────
if [[ "$UPDATE_FGT_ONLY" == "true" ]]; then
    print_section "UPDATING FORTIGATE IPS ONLY"
    if [[ ! -f "$MD_FILE" ]]; then
        print_fail "network_diagram.md not found — run without --update-fgt first"
        exit 1
    fi

    print_info "Querying FortiGate instances..."
    for region in us-east-1 us-west-2; do
        r="${region/-1/}"; r="${r/-2/}"; r="${r/us-/}"  # "east" or "west"
        [[ "$region" == "us-east-1" ]] && r="east" || r="west"
        for role in primary secondary; do
            name="${PREFIX}-${r}-fgt-${role}"
            iid=$(get_instance_attr "$region" "$name" "InstanceId")
            pip=$(get_instance_attr "$region" "$name" "PrivateIpAddress")
            eip=""
            if [[ "$role" == "primary" ]]; then
                eip=$(get_eip "$region" "${PREFIX}-${r}-fgt-cluster-eip")
                mgmt=$(get_eip "$region" "${PREFIX}-${r}-fgt-primary-mgmt-eip")
            else
                mgmt=$(get_eip "$region" "${PREFIX}-${r}-fgt-secondary-mgmt-eip")
            fi
            [[ -z "$iid"  ]] && iid="—"
            [[ -z "$pip"  ]] && pip="—"
            [[ -z "$eip"  ]] && eip="—"
            [[ -z "$mgmt" ]] && mgmt="—"
            printf "[%s] %-40s  id=%-20s  port1=%s  mgmt=%s\n" "$region" "$name" "$iid" "$eip" "$mgmt"
        done
    done

    # Rebuild FortiGate table and splice into MD
    FGT_TABLE="| Region | Instance | Instance ID | port2 IP | Cluster/Mgmt EIP |\n"
    FGT_TABLE+="|--------|----------|-------------|----------|------------------|\n"
    for region in us-east-1 us-west-2; do
        [[ "$region" == "us-east-1" ]] && r="east" || r="west"
        for role in primary secondary; do
            name="${PREFIX}-${r}-fgt-${role}"
            iid=$(get_instance_attr "$region" "$name" "InstanceId"); [[ -z "$iid" ]] && iid="—"
            pip=$(get_instance_attr "$region" "$name" "PrivateIpAddress"); [[ -z "$pip" ]] && pip="—"
            if [[ "$role" == "primary" ]]; then
                eip=$(get_eip "$region" "${PREFIX}-${r}-fgt-cluster-eip"); [[ -z "$eip" ]] && eip="—"
                mgmt=$(get_eip "$region" "${PREFIX}-${r}-fgt-primary-mgmt-eip"); [[ -z "$mgmt" ]] && mgmt="—"
                eip_col="${eip} / ${mgmt}"
            else
                mgmt=$(get_eip "$region" "${PREFIX}-${r}-fgt-secondary-mgmt-eip"); [[ -z "$mgmt" ]] && mgmt="—"
                eip_col="— / ${mgmt}"
            fi
            FGT_TABLE+="| ${region} | ${name} | ${iid} | ${pip} | ${eip_col} |\n"
        done
    done

    NEW_FGT_SECTION="### FortiGate Instances

$(printf "%b" "$FGT_TABLE")
> port2 is the Cloud WAN BGP peer interface."

    awk -v new="$NEW_FGT_SECTION" '
        /^### FortiGate Instances$/ { print new; in_sec=1; next }
        in_sec && /^(###|---)/ { in_sec=0 }
        !in_sec { print }
    ' "$MD_FILE" > "${MD_FILE}.tmp" && mv "${MD_FILE}.tmp" "$MD_FILE"

    print_pass "FortiGate section updated: $MD_FILE"
    exit 0
fi

# ── Full generation: query AWS ──────────────────────────────────────────────
print_section "QUERYING AWS — us-east-1"

EAST_INSP_VPC_ID=$(get_vpc_id    "us-east-1" "${PREFIX}-east-inspection-vpc")
EAST_SPOKE_A_ID=$(get_vpc_id     "us-east-1" "${PREFIX}-east-spoke-a-vpc")
EAST_SPOKE_B_ID=$(get_vpc_id     "us-east-1" "${PREFIX}-east-spoke-b-vpc")
EAST_FGT_PRI_ID=$(get_instance_attr  "us-east-1" "${PREFIX}-east-fgt-primary"   "InstanceId")
EAST_FGT_PRI_P1=$(get_eip           "us-east-1" "${PREFIX}-east-fgt-cluster-eip")
EAST_FGT_PRI_MGMT=$(get_eip         "us-east-1" "${PREFIX}-east-fgt-primary-mgmt-eip")
EAST_FGT_SEC_ID=$(get_instance_attr  "us-east-1" "${PREFIX}-east-fgt-secondary" "InstanceId")
EAST_FGT_SEC_MGMT=$(get_eip         "us-east-1" "${PREFIX}-east-fgt-secondary-mgmt-eip")

[[ -n "$EAST_INSP_VPC_ID" ]]  && print_pass "East inspection VPC: $EAST_INSP_VPC_ID"  || print_info "East inspection VPC: not deployed"
[[ -n "$EAST_FGT_PRI_ID" ]]  && print_pass "East FGT primary:    $EAST_FGT_PRI_ID"   || print_info "East FGT primary:    not deployed"
[[ -n "$EAST_FGT_SEC_ID" ]]  && print_pass "East FGT secondary:  $EAST_FGT_SEC_ID"   || print_info "East FGT secondary:  not deployed"

print_section "QUERYING AWS — us-west-2"

WEST_INSP_VPC_ID=$(get_vpc_id    "us-west-2" "${PREFIX}-west-inspection-vpc")
WEST_SPOKE_A_ID=$(get_vpc_id     "us-west-2" "${PREFIX}-west-spoke-a-vpc")
WEST_SPOKE_B_ID=$(get_vpc_id     "us-west-2" "${PREFIX}-west-spoke-b-vpc")
WEST_FGT_PRI_ID=$(get_instance_attr  "us-west-2" "${PREFIX}-west-fgt-primary"   "InstanceId")
WEST_FGT_PRI_P1=$(get_eip           "us-west-2" "${PREFIX}-west-fgt-cluster-eip")
WEST_FGT_PRI_MGMT=$(get_eip         "us-west-2" "${PREFIX}-west-fgt-primary-mgmt-eip")
WEST_FGT_SEC_ID=$(get_instance_attr  "us-west-2" "${PREFIX}-west-fgt-secondary" "InstanceId")
WEST_FGT_SEC_MGMT=$(get_eip         "us-west-2" "${PREFIX}-west-fgt-secondary-mgmt-eip")

[[ -n "$WEST_INSP_VPC_ID" ]] && print_pass "West inspection VPC: $WEST_INSP_VPC_ID"  || print_info "West inspection VPC: not deployed"
[[ -n "$WEST_FGT_PRI_ID" ]] && print_pass "West FGT primary:    $WEST_FGT_PRI_ID"   || print_info "West FGT primary:    not deployed"
[[ -n "$WEST_FGT_SEC_ID" ]] && print_pass "West FGT secondary:  $WEST_FGT_SEC_ID"   || print_info "West FGT secondary:  not deployed"

print_section "QUERYING CLOUD WAN"

GLOBAL_NET_ID=$(aws networkmanager list-global-networks \
    --query 'GlobalNetworks[0].GlobalNetworkId' --output text 2>/dev/null | grep -v None || echo "")

CORE_NET_ID=""
EAST_PRI_PEER_STATE="—"; EAST_SEC_PEER_STATE="—"
WEST_PRI_PEER_STATE="—"; WEST_SEC_PEER_STATE="—"

if [[ -n "$GLOBAL_NET_ID" ]]; then
    print_pass "Global Network: $GLOBAL_NET_ID"
    CORE_NET_ID=$(aws networkmanager list-core-networks \
        --query "CoreNetworks[?GlobalNetworkId=='${GLOBAL_NET_ID}'].CoreNetworkId | [0]" \
        --output text 2>/dev/null | grep -v None || echo "")
    [[ -n "$CORE_NET_ID" ]] && print_pass "Core Network: $CORE_NET_ID" || print_info "Core Network: not yet provisioned"
fi

if [[ -n "$CORE_NET_ID" ]]; then
    PEERS_JSON=$(aws networkmanager list-connect-peers \
        --core-network-id "$CORE_NET_ID" \
        --query 'ConnectPeers[*].[Tags[?Key==`Name`].Value|[0],State]' \
        --output json 2>/dev/null || echo "[]")

    EAST_PRI_PEER_STATE=$(echo "$PEERS_JSON" | jq -r ".[] | select(.[0]==\"${PREFIX}-east-fgt-primary-peer\")   | .[1]" 2>/dev/null || echo "")
    EAST_SEC_PEER_STATE=$(echo "$PEERS_JSON" | jq -r ".[] | select(.[0]==\"${PREFIX}-east-fgt-secondary-peer\") | .[1]" 2>/dev/null || echo "")
    WEST_PRI_PEER_STATE=$(echo "$PEERS_JSON" | jq -r ".[] | select(.[0]==\"${PREFIX}-west-fgt-primary-peer\")   | .[1]" 2>/dev/null || echo "")
    WEST_SEC_PEER_STATE=$(echo "$PEERS_JSON" | jq -r ".[] | select(.[0]==\"${PREFIX}-west-fgt-secondary-peer\") | .[1]" 2>/dev/null || echo "")

    for var in EAST_PRI_PEER_STATE EAST_SEC_PEER_STATE WEST_PRI_PEER_STATE WEST_SEC_PEER_STATE; do
        [[ -z "${!var}" ]] && printf -v "$var" "—"
    done
fi

# ── Fill display defaults ───────────────────────────────────────────────────
d() { [[ -z "$1" ]] && echo "$2" || echo "$1"; }

EAST_INSP_VPC_ID=$(d "$EAST_INSP_VPC_ID" "not deployed")
EAST_SPOKE_A_ID=$(d  "$EAST_SPOKE_A_ID"  "not deployed")
EAST_SPOKE_B_ID=$(d  "$EAST_SPOKE_B_ID"  "not deployed")
EAST_FGT_PRI_ID=$(d  "$EAST_FGT_PRI_ID"  "—")
EAST_FGT_PRI_P1=$(d  "$EAST_FGT_PRI_P1"  "—")
EAST_FGT_PRI_MGMT=$(d "$EAST_FGT_PRI_MGMT" "—")
EAST_FGT_SEC_ID=$(d  "$EAST_FGT_SEC_ID"  "—")
EAST_FGT_SEC_MGMT=$(d "$EAST_FGT_SEC_MGMT" "—")
WEST_INSP_VPC_ID=$(d "$WEST_INSP_VPC_ID" "not deployed")
WEST_SPOKE_A_ID=$(d  "$WEST_SPOKE_A_ID"  "not deployed")
WEST_SPOKE_B_ID=$(d  "$WEST_SPOKE_B_ID"  "not deployed")
WEST_FGT_PRI_ID=$(d  "$WEST_FGT_PRI_ID"  "—")
WEST_FGT_PRI_P1=$(d  "$WEST_FGT_PRI_P1"  "—")
WEST_FGT_PRI_MGMT=$(d "$WEST_FGT_PRI_MGMT" "—")
WEST_FGT_SEC_ID=$(d  "$WEST_FGT_SEC_ID"  "—")
WEST_FGT_SEC_MGMT=$(d "$WEST_FGT_SEC_MGMT" "—")
GLOBAL_NET_ID=$(d "$GLOBAL_NET_ID" "not deployed")
CORE_NET_ID=$(d   "$CORE_NET_ID"   "not deployed")

# SVG status colours
svg_fgt_color() { [[ "$1" == "—" ]] && echo "#888888" || echo "#007700"; }
svg_peer_color() {
    case "$1" in
        AVAILABLE) echo "#007700" ;;
        PENDING)   echo "#CC8800" ;;
        *)         echo "#888888" ;;
    esac
}
EAST_PRI_FGT_COL=$(svg_fgt_color  "$EAST_FGT_PRI_ID")
EAST_SEC_FGT_COL=$(svg_fgt_color  "$EAST_FGT_SEC_ID")
WEST_PRI_FGT_COL=$(svg_fgt_color  "$WEST_FGT_PRI_ID")
WEST_SEC_FGT_COL=$(svg_fgt_color  "$WEST_FGT_SEC_ID")
EAST_PRI_PEER_COL=$(svg_peer_color "$EAST_PRI_PEER_STATE")
EAST_SEC_PEER_COL=$(svg_peer_color "$EAST_SEC_PEER_STATE")
WEST_PRI_PEER_COL=$(svg_peer_color "$WEST_PRI_PEER_STATE")
WEST_SEC_PEER_COL=$(svg_peer_color "$WEST_SEC_PEER_STATE")

# ── Generate SVG ────────────────────────────────────────────────────────────
print_section "GENERATING SVG"
print_info "Output: $SVG_FILE"

cat > "$SVG_FILE" << SVGEOF
<?xml version="1.0" encoding="UTF-8"?>
<!--
  Tunnelless CloudWAN — network diagram
  Generated: ${TIMESTAMP}
  Prefix: ${PREFIX}
-->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2400 1420" font-family="Arial, sans-serif">
  <defs>
    <linearGradient id="greenGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%"   style="stop-color:#C8E6C9"/>
      <stop offset="100%" style="stop-color:#A5D6A7"/>
    </linearGradient>
    <linearGradient id="blueGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%"   style="stop-color:#BBDEFB"/>
      <stop offset="100%" style="stop-color:#90CAF9"/>
    </linearGradient>
    <linearGradient id="purpleGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%"   style="stop-color:#E1BEE7"/>
      <stop offset="100%" style="stop-color:#CE93D8"/>
    </linearGradient>
    <linearGradient id="orangeGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%"   style="stop-color:#FFE0B2"/>
      <stop offset="100%" style="stop-color:#FFCC80"/>
    </linearGradient>
    <linearGradient id="cwGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%"   style="stop-color:#1A237E"/>
      <stop offset="50%"  style="stop-color:#283593"/>
      <stop offset="100%" style="stop-color:#1A237E"/>
    </linearGradient>
    <marker id="arrowBlue" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
      <polygon points="0 0, 8 3, 0 6" fill="#1565C0"/>
    </marker>
    <marker id="arrowGray" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
      <polygon points="0 0, 8 3, 0 6" fill="#555555"/>
    </marker>
    <marker id="arrowRed" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
      <polygon points="0 0, 8 3, 0 6" fill="#EE3124"/>
    </marker>
  </defs>

  <!-- Background -->
  <rect width="2400" height="1420" fill="#F5F5F5"/>

  <!-- ── Title ── -->
  <text x="1200" y="42" text-anchor="middle" fill="#1A237E" font-size="28" font-weight="bold">${PREFIX} — AWS Cloud WAN Tunnelless Connect</text>
  <text x="1200" y="68" text-anchor="middle" fill="#555555" font-size="16">Generated: ${TIMESTAMP} | FortiGate ASN ${FGT_ASN} | East CNE ASN ${CNE_ASN_EAST} | West CNE ASN ${CNE_ASN_WEST}</text>

  <!-- ══════════════════════════════════════════════════════════════════════
       LEFT REGION: us-east-1
       Region box: (15, 78) w=1105 h=1005
       ══════════════════════════════════════════════════════════════════════ -->
  <rect x="15" y="78" width="1105" height="1005" rx="8" fill="#E3F2FD" stroke="#1565C0" stroke-width="2.5" opacity="0.6"/>
  <text x="35" y="104" fill="#0D47A1" font-size="20" font-weight="bold">us-east-1</text>

  <!-- East Inspection VPC box -->
  <rect x="30" y="112" width="1075" height="545" rx="6" fill="white" stroke="#3B48CC" stroke-width="2"/>
  <text x="50" y="137" fill="#1A237E" font-size="18" font-weight="bold">Inspection VPC</text>
  <text x="50" y="158" fill="#555555" font-size="14">${EAST_INSP_VPC_ID} | ${EAST_INSP_VPC_CIDR}</text>

  <!-- East FGT Primary box -->
  <rect x="48" y="168" width="490" height="228" rx="5" fill="none" stroke="#EE3124" stroke-width="2"/>
  <text x="68" y="193" fill="#EE3124" font-size="17" font-weight="bold">FortiGate Primary (AZ1 — port3)</text>
  <text x="68" y="216" fill="${EAST_PRI_FGT_COL}" font-size="14">${PREFIX}-east-fgt-primary</text>
  <text x="68" y="237" fill="#333333" font-size="13">ID:    ${EAST_FGT_PRI_ID}</text>
  <text x="68" y="256" fill="#333333" font-size="13">port1: ${EAST_FGT_PRI_P1} (cluster EIP)</text>
  <text x="68" y="275" fill="#333333" font-size="13">port2: ${EAST_FGT_PRI_P2} (BGP peer)</text>
  <text x="68" y="294" fill="#333333" font-size="13">port3: ${EAST_FGT_PRI_MGMT} (mgmt EIP)</text>
  <text x="68" y="316" fill="#555555" font-size="13" font-style="italic">eBGP → ${EAST_CNE_BGP_PRI} (ASN ${CNE_ASN_EAST})</text>
  <text x="68" y="337" fill="${EAST_PRI_PEER_COL}" font-size="13">Connect Peer: ${EAST_PRI_PEER_STATE}</text>
  <text x="68" y="385" fill="#333333" font-size="13">HA: Active/Primary | FGCP group: ${PREFIX}-east</text>

  <!-- East FGT Secondary box -->
  <rect x="48" y="410" width="490" height="228" rx="5" fill="none" stroke="#EE3124" stroke-width="1.5" stroke-dasharray="6,4"/>
  <text x="68" y="435" fill="#EE3124" font-size="17" font-weight="bold">FortiGate Secondary (AZ2 — port3)</text>
  <text x="68" y="456" fill="${EAST_SEC_FGT_COL}" font-size="14">${PREFIX}-east-fgt-secondary</text>
  <text x="68" y="477" fill="#333333" font-size="13">ID:    ${EAST_FGT_SEC_ID}</text>
  <text x="68" y="496" fill="#333333" font-size="13">port1: — (no EIP on standby)</text>
  <text x="68" y="515" fill="#333333" font-size="13">port2: ${EAST_FGT_SEC_P2} (BGP peer)</text>
  <text x="68" y="534" fill="#333333" font-size="13">port3: ${EAST_FGT_SEC_MGMT} (mgmt EIP)</text>
  <text x="68" y="556" fill="#555555" font-size="13" font-style="italic">eBGP → ${EAST_CNE_BGP_SEC} (ASN ${CNE_ASN_EAST})</text>
  <text x="68" y="577" fill="${EAST_SEC_PEER_COL}" font-size="13">Connect Peer: ${EAST_SEC_PEER_STATE}</text>

  <!-- East Inspection VPC subnet panel -->
  <!-- Public subnets -->
  <rect x="558" y="168" width="240" height="88" rx="4" fill="url(#greenGrad)"/>
  <text x="678" y="192" text-anchor="middle" fill="#1B5E20" font-size="14" font-weight="bold">Public AZ1</text>
  <text x="678" y="212" text-anchor="middle" fill="#333333" font-size="13">${EAST_PUB_AZ1}</text>
  <text x="678" y="230" text-anchor="middle" fill="#555555" font-size="12">port1 / IGW / EIP</text>
  <text x="678" y="248" text-anchor="middle" fill="#777777" font-size="11">0.0.0.0/0 → IGW</text>

  <rect x="812" y="168" width="240" height="88" rx="4" fill="url(#greenGrad)"/>
  <text x="932" y="192" text-anchor="middle" fill="#1B5E20" font-size="14" font-weight="bold">Public AZ2</text>
  <text x="932" y="212" text-anchor="middle" fill="#333333" font-size="13">${EAST_PUB_AZ2}</text>
  <text x="932" y="230" text-anchor="middle" fill="#555555" font-size="12">port1 (standby)</text>
  <text x="932" y="248" text-anchor="middle" fill="#777777" font-size="11">0.0.0.0/0 → IGW</text>

  <!-- Private subnets -->
  <rect x="558" y="270" width="240" height="88" rx="4" fill="url(#blueGrad)"/>
  <text x="678" y="294" text-anchor="middle" fill="#0D47A1" font-size="14" font-weight="bold">Private AZ1</text>
  <text x="678" y="314" text-anchor="middle" fill="#333333" font-size="13">${EAST_PRIV_AZ1}</text>
  <text x="678" y="332" text-anchor="middle" fill="#555555" font-size="12">port2 / CW VPC attach</text>
  <text x="678" y="350" text-anchor="middle" fill="#777777" font-size="11">CNE BGP: ${EAST_CNE_BGP_PRI}</text>

  <rect x="812" y="270" width="240" height="88" rx="4" fill="url(#blueGrad)"/>
  <text x="932" y="294" text-anchor="middle" fill="#0D47A1" font-size="14" font-weight="bold">Private AZ2</text>
  <text x="932" y="314" text-anchor="middle" fill="#333333" font-size="13">${EAST_PRIV_AZ2}</text>
  <text x="932" y="332" text-anchor="middle" fill="#555555" font-size="12">port2 / CW VPC attach</text>
  <text x="932" y="350" text-anchor="middle" fill="#777777" font-size="11">CNE BGP: ${EAST_CNE_BGP_SEC}</text>

  <!-- HA sync subnets -->
  <rect x="558" y="372" width="240" height="88" rx="4" fill="url(#orangeGrad)"/>
  <text x="678" y="396" text-anchor="middle" fill="#E65100" font-size="14" font-weight="bold">HA-sync AZ1</text>
  <text x="678" y="416" text-anchor="middle" fill="#333333" font-size="13">${EAST_HA_AZ1}</text>
  <text x="678" y="434" text-anchor="middle" fill="#555555" font-size="12">port3 / FGCP heartbeat</text>
  <text x="678" y="452" text-anchor="middle" fill="#777777" font-size="11">EC2 endpoint / mgmt</text>

  <rect x="812" y="372" width="240" height="88" rx="4" fill="url(#orangeGrad)"/>
  <text x="932" y="396" text-anchor="middle" fill="#E65100" font-size="14" font-weight="bold">HA-sync AZ2</text>
  <text x="932" y="416" text-anchor="middle" fill="#333333" font-size="13">${EAST_HA_AZ2}</text>
  <text x="932" y="434" text-anchor="middle" fill="#555555" font-size="12">port3 / FGCP heartbeat</text>
  <text x="932" y="452" text-anchor="middle" fill="#777777" font-size="11">EC2 endpoint / mgmt</text>

  <!-- East Connect + VPC attachment labels -->
  <rect x="558" y="474" width="494" height="44" rx="4" fill="url(#purpleGrad)"/>
  <text x="805" y="492" text-anchor="middle" fill="#4A148C" font-size="13" font-weight="bold">Connect Attachment (NO_ENCAP) — over inspection VPC attachment</text>
  <text x="805" y="511" text-anchor="middle" fill="#4A148C" font-size="12">2 Connect Peers: primary (.10 AZ1) + secondary (.10 AZ2) | ASN ${FGT_ASN}</text>

  <rect x="558" y="524" width="494" height="38" rx="4" fill="#E8EAF6" stroke="#7986CB" stroke-width="1"/>
  <text x="805" y="547" text-anchor="middle" fill="#283593" font-size="13">VPC Attachment (inspection) — ${EAST_INSP_VPC_ID}</text>

  <!-- East Spoke A VPC -->
  <rect x="30" y="672" width="510" height="238" rx="6" fill="white" stroke="#2E7D32" stroke-width="1.5"/>
  <text x="50" y="698" fill="#1B5E20" font-size="17" font-weight="bold">Spoke A VPC</text>
  <text x="50" y="718" fill="#555555" font-size="13">${EAST_SPOKE_A_ID}</text>
  <text x="50" y="737" fill="#333333" font-size="14">${EAST_SPOKE_A_CIDR}</text>
  <text x="50" y="762" fill="#555555" font-size="13">Test instance</text>
  <text x="50" y="794" fill="#777777" font-size="13">0.0.0.0/0 → Core Network</text>
  <text x="50" y="815" fill="#777777" font-size="12" font-style="italic">(VPC attachment to Cloud WAN)</text>
  <rect x="50" y="850" width="470" height="44" rx="3" fill="#E8EAF6" stroke="#7986CB" stroke-width="1"/>
  <text x="285" y="877" text-anchor="middle" fill="#283593" font-size="13">VPC Attachment → Cloud WAN | segment: production</text>

  <!-- East Spoke B VPC -->
  <rect x="560" y="672" width="510" height="238" rx="6" fill="white" stroke="#2E7D32" stroke-width="1.5"/>
  <text x="580" y="698" fill="#1B5E20" font-size="17" font-weight="bold">Spoke B VPC</text>
  <text x="580" y="718" fill="#555555" font-size="13">${EAST_SPOKE_B_ID}</text>
  <text x="580" y="737" fill="#333333" font-size="14">${EAST_SPOKE_B_CIDR}</text>
  <text x="580" y="762" fill="#555555" font-size="13">Test instance</text>
  <text x="580" y="794" fill="#777777" font-size="13">0.0.0.0/0 → Core Network</text>
  <text x="580" y="815" fill="#777777" font-size="12" font-style="italic">(VPC attachment to Cloud WAN)</text>
  <rect x="580" y="850" width="470" height="44" rx="3" fill="#E8EAF6" stroke="#7986CB" stroke-width="1"/>
  <text x="815" y="877" text-anchor="middle" fill="#283593" font-size="13">VPC Attachment → Cloud WAN | segment: production</text>

  <!-- ══════════════════════════════════════════════════════════════════════
       RIGHT REGION: us-west-2
       Region box: (1280, 78) w=1105 h=1005
       ══════════════════════════════════════════════════════════════════════ -->
  <rect x="1280" y="78" width="1105" height="1005" rx="8" fill="#FFF3E0" stroke="#E65100" stroke-width="2.5" opacity="0.6"/>
  <text x="1300" y="104" fill="#BF360C" font-size="20" font-weight="bold">us-west-2</text>

  <!-- West Inspection VPC box -->
  <rect x="1295" y="112" width="1075" height="545" rx="6" fill="white" stroke="#3B48CC" stroke-width="2"/>
  <text x="1315" y="137" fill="#1A237E" font-size="18" font-weight="bold">Inspection VPC</text>
  <text x="1315" y="158" fill="#555555" font-size="14">${WEST_INSP_VPC_ID} | ${WEST_INSP_VPC_CIDR}</text>

  <!-- West FGT Primary box -->
  <rect x="1313" y="168" width="490" height="228" rx="5" fill="none" stroke="#EE3124" stroke-width="2"/>
  <text x="1333" y="193" fill="#EE3124" font-size="17" font-weight="bold">FortiGate Primary (AZ1 — port3)</text>
  <text x="1333" y="216" fill="${WEST_PRI_FGT_COL}" font-size="14">${PREFIX}-west-fgt-primary</text>
  <text x="1333" y="237" fill="#333333" font-size="13">ID:    ${WEST_FGT_PRI_ID}</text>
  <text x="1333" y="256" fill="#333333" font-size="13">port1: ${WEST_FGT_PRI_P1} (cluster EIP)</text>
  <text x="1333" y="275" fill="#333333" font-size="13">port2: ${WEST_FGT_PRI_P2} (BGP peer)</text>
  <text x="1333" y="294" fill="#333333" font-size="13">port3: ${WEST_FGT_PRI_MGMT} (mgmt EIP)</text>
  <text x="1333" y="316" fill="#555555" font-size="13" font-style="italic">eBGP → ${WEST_CNE_BGP_PRI} (ASN ${CNE_ASN_WEST})</text>
  <text x="1333" y="337" fill="${WEST_PRI_PEER_COL}" font-size="13">Connect Peer: ${WEST_PRI_PEER_STATE}</text>
  <text x="1333" y="385" fill="#333333" font-size="13">HA: Active/Primary | FGCP group: ${PREFIX}-west</text>

  <!-- West FGT Secondary box -->
  <rect x="1313" y="410" width="490" height="228" rx="5" fill="none" stroke="#EE3124" stroke-width="1.5" stroke-dasharray="6,4"/>
  <text x="1333" y="435" fill="#EE3124" font-size="17" font-weight="bold">FortiGate Secondary (AZ2 — port3)</text>
  <text x="1333" y="456" fill="${WEST_SEC_FGT_COL}" font-size="14">${PREFIX}-west-fgt-secondary</text>
  <text x="1333" y="477" fill="#333333" font-size="13">ID:    ${WEST_FGT_SEC_ID}</text>
  <text x="1333" y="496" fill="#333333" font-size="13">port1: — (no EIP on standby)</text>
  <text x="1333" y="515" fill="#333333" font-size="13">port2: ${WEST_FGT_SEC_P2} (BGP peer)</text>
  <text x="1333" y="534" fill="#333333" font-size="13">port3: ${WEST_FGT_SEC_MGMT} (mgmt EIP)</text>
  <text x="1333" y="556" fill="#555555" font-size="13" font-style="italic">eBGP → ${WEST_CNE_BGP_SEC} (ASN ${CNE_ASN_WEST})</text>
  <text x="1333" y="577" fill="${WEST_SEC_PEER_COL}" font-size="13">Connect Peer: ${WEST_SEC_PEER_STATE}</text>

  <!-- West Inspection VPC subnet panel -->
  <rect x="1823" y="168" width="240" height="88" rx="4" fill="url(#greenGrad)"/>
  <text x="1943" y="192" text-anchor="middle" fill="#1B5E20" font-size="14" font-weight="bold">Public AZ1</text>
  <text x="1943" y="212" text-anchor="middle" fill="#333333" font-size="13">${WEST_PUB_AZ1}</text>
  <text x="1943" y="230" text-anchor="middle" fill="#555555" font-size="12">port1 / IGW / EIP</text>
  <text x="1943" y="248" text-anchor="middle" fill="#777777" font-size="11">0.0.0.0/0 → IGW</text>

  <rect x="2077" y="168" width="240" height="88" rx="4" fill="url(#greenGrad)"/>
  <text x="2197" y="192" text-anchor="middle" fill="#1B5E20" font-size="14" font-weight="bold">Public AZ2</text>
  <text x="2197" y="212" text-anchor="middle" fill="#333333" font-size="13">${WEST_PUB_AZ2}</text>
  <text x="2197" y="230" text-anchor="middle" fill="#555555" font-size="12">port1 (standby)</text>
  <text x="2197" y="248" text-anchor="middle" fill="#777777" font-size="11">0.0.0.0/0 → IGW</text>

  <rect x="1823" y="270" width="240" height="88" rx="4" fill="url(#blueGrad)"/>
  <text x="1943" y="294" text-anchor="middle" fill="#0D47A1" font-size="14" font-weight="bold">Private AZ1</text>
  <text x="1943" y="314" text-anchor="middle" fill="#333333" font-size="13">${WEST_PRIV_AZ1}</text>
  <text x="1943" y="332" text-anchor="middle" fill="#555555" font-size="12">port2 / CW VPC attach</text>
  <text x="1943" y="350" text-anchor="middle" fill="#777777" font-size="11">CNE BGP: ${WEST_CNE_BGP_PRI}</text>

  <rect x="2077" y="270" width="240" height="88" rx="4" fill="url(#blueGrad)"/>
  <text x="2197" y="294" text-anchor="middle" fill="#0D47A1" font-size="14" font-weight="bold">Private AZ2</text>
  <text x="2197" y="314" text-anchor="middle" fill="#333333" font-size="13">${WEST_PRIV_AZ2}</text>
  <text x="2197" y="332" text-anchor="middle" fill="#555555" font-size="12">port2 / CW VPC attach</text>
  <text x="2197" y="350" text-anchor="middle" fill="#777777" font-size="11">CNE BGP: ${WEST_CNE_BGP_SEC}</text>

  <rect x="1823" y="372" width="240" height="88" rx="4" fill="url(#orangeGrad)"/>
  <text x="1943" y="396" text-anchor="middle" fill="#E65100" font-size="14" font-weight="bold">HA-sync AZ1</text>
  <text x="1943" y="416" text-anchor="middle" fill="#333333" font-size="13">${WEST_HA_AZ1}</text>
  <text x="1943" y="434" text-anchor="middle" fill="#555555" font-size="12">port3 / FGCP heartbeat</text>
  <text x="1943" y="452" text-anchor="middle" fill="#777777" font-size="11">EC2 endpoint / mgmt</text>

  <rect x="2077" y="372" width="240" height="88" rx="4" fill="url(#orangeGrad)"/>
  <text x="2197" y="396" text-anchor="middle" fill="#E65100" font-size="14" font-weight="bold">HA-sync AZ2</text>
  <text x="2197" y="416" text-anchor="middle" fill="#333333" font-size="13">${WEST_HA_AZ2}</text>
  <text x="2197" y="434" text-anchor="middle" fill="#555555" font-size="12">port3 / FGCP heartbeat</text>
  <text x="2197" y="452" text-anchor="middle" fill="#777777" font-size="11">EC2 endpoint / mgmt</text>

  <rect x="1823" y="474" width="494" height="44" rx="4" fill="url(#purpleGrad)"/>
  <text x="2070" y="492" text-anchor="middle" fill="#4A148C" font-size="13" font-weight="bold">Connect Attachment (NO_ENCAP) — over inspection VPC attachment</text>
  <text x="2070" y="511" text-anchor="middle" fill="#4A148C" font-size="12">2 Connect Peers: primary (.10 AZ1) + secondary (.10 AZ2) | ASN ${FGT_ASN}</text>

  <rect x="1823" y="524" width="494" height="38" rx="4" fill="#E8EAF6" stroke="#7986CB" stroke-width="1"/>
  <text x="2070" y="547" text-anchor="middle" fill="#283593" font-size="13">VPC Attachment (inspection) — ${WEST_INSP_VPC_ID}</text>

  <!-- West Spoke A VPC -->
  <rect x="1295" y="672" width="510" height="238" rx="6" fill="white" stroke="#2E7D32" stroke-width="1.5"/>
  <text x="1315" y="698" fill="#1B5E20" font-size="17" font-weight="bold">Spoke A VPC</text>
  <text x="1315" y="718" fill="#555555" font-size="13">${WEST_SPOKE_A_ID}</text>
  <text x="1315" y="737" fill="#333333" font-size="14">${WEST_SPOKE_A_CIDR}</text>
  <text x="1315" y="762" fill="#555555" font-size="13">Test instance</text>
  <text x="1315" y="794" fill="#777777" font-size="13">0.0.0.0/0 → Core Network</text>
  <text x="1315" y="815" fill="#777777" font-size="12" font-style="italic">(VPC attachment to Cloud WAN)</text>
  <rect x="1315" y="850" width="470" height="44" rx="3" fill="#E8EAF6" stroke="#7986CB" stroke-width="1"/>
  <text x="1550" y="877" text-anchor="middle" fill="#283593" font-size="13">VPC Attachment → Cloud WAN | segment: production</text>

  <!-- West Spoke B VPC -->
  <rect x="1825" y="672" width="510" height="238" rx="6" fill="white" stroke="#2E7D32" stroke-width="1.5"/>
  <text x="1845" y="698" fill="#1B5E20" font-size="17" font-weight="bold">Spoke B VPC</text>
  <text x="1845" y="718" fill="#555555" font-size="13">${WEST_SPOKE_B_ID}</text>
  <text x="1845" y="737" fill="#333333" font-size="14">${WEST_SPOKE_B_CIDR}</text>
  <text x="1845" y="762" fill="#555555" font-size="13">Test instance</text>
  <text x="1845" y="794" fill="#777777" font-size="13">0.0.0.0/0 → Core Network</text>
  <text x="1845" y="815" fill="#777777" font-size="12" font-style="italic">(VPC attachment to Cloud WAN)</text>
  <rect x="1845" y="850" width="470" height="44" rx="3" fill="#E8EAF6" stroke="#7986CB" stroke-width="1"/>
  <text x="2080" y="877" text-anchor="middle" fill="#283593" font-size="13">VPC Attachment → Cloud WAN | segment: production</text>

  <!-- ══════════════════════════════════════════════════════════════════════
       CONNECTION LINES (inspection VPCs + spokes → Cloud WAN)
       ══════════════════════════════════════════════════════════════════════ -->

  <!-- East inspection VPC eBGP → Cloud WAN (from FGT area center x≈295) -->
  <line x1="295" y1="657" x2="295" y2="1105"
        stroke="#EE3124" stroke-width="2" stroke-dasharray="8,4"
        marker-end="url(#arrowRed)"/>
  <rect x="200" y="860" width="190" height="28" rx="4" fill="white" opacity="0.85"/>
  <text x="295" y="878" text-anchor="middle" fill="#EE3124" font-size="13" font-weight="bold">eBGP / Connect</text>

  <!-- East Spoke A → Cloud WAN -->
  <line x1="285" y1="910" x2="285" y2="1105"
        stroke="#283593" stroke-width="1.5" stroke-dasharray="5,3"
        marker-end="url(#arrowBlue)"/>
  <rect x="172" y="960" width="226" height="24" rx="3" fill="white" opacity="0.85"/>
  <text x="285" y="976" text-anchor="middle" fill="#283593" font-size="12">VPC Attach (spoke-a)</text>

  <!-- East Spoke B → Cloud WAN -->
  <line x1="815" y1="910" x2="815" y2="1105"
        stroke="#283593" stroke-width="1.5" stroke-dasharray="5,3"
        marker-end="url(#arrowBlue)"/>
  <rect x="702" y="960" width="226" height="24" rx="3" fill="white" opacity="0.85"/>
  <text x="815" y="976" text-anchor="middle" fill="#283593" font-size="12">VPC Attach (spoke-b)</text>

  <!-- West inspection VPC eBGP → Cloud WAN (from FGT area center x≈1560) -->
  <line x1="1560" y1="657" x2="1560" y2="1105"
        stroke="#EE3124" stroke-width="2" stroke-dasharray="8,4"
        marker-end="url(#arrowRed)"/>
  <rect x="1460" y="860" width="200" height="28" rx="4" fill="white" opacity="0.85"/>
  <text x="1560" y="878" text-anchor="middle" fill="#EE3124" font-size="13" font-weight="bold">eBGP / Connect</text>

  <!-- West Spoke A → Cloud WAN -->
  <line x1="1550" y1="910" x2="1550" y2="1105"
        stroke="#283593" stroke-width="1.5" stroke-dasharray="5,3"
        marker-end="url(#arrowBlue)"/>
  <rect x="1437" y="960" width="226" height="24" rx="3" fill="white" opacity="0.85"/>
  <text x="1550" y="976" text-anchor="middle" fill="#283593" font-size="12">VPC Attach (spoke-a)</text>

  <!-- West Spoke B → Cloud WAN -->
  <line x1="2080" y1="910" x2="2080" y2="1105"
        stroke="#283593" stroke-width="1.5" stroke-dasharray="5,3"
        marker-end="url(#arrowBlue)"/>
  <rect x="1967" y="960" width="226" height="24" rx="3" fill="white" opacity="0.85"/>
  <text x="2080" y="976" text-anchor="middle" fill="#283593" font-size="12">VPC Attach (spoke-b)</text>

  <!-- ══════════════════════════════════════════════════════════════════════
       AWS CLOUD WAN BACKBONE
       Box: (15, 1108) w=2370 h=268
       ══════════════════════════════════════════════════════════════════════ -->
  <rect x="15" y="1108" width="2370" height="268" rx="8" fill="url(#cwGrad)"/>
  <text x="1200" y="1148" text-anchor="middle" fill="#FFFFFF" font-size="22" font-weight="bold">AWS Cloud WAN — Global Backbone (no tunnels)</text>
  <text x="1200" y="1174" text-anchor="middle" fill="#90CAF9" font-size="15">Global Network: ${GLOBAL_NET_ID} | Core Network: ${CORE_NET_ID}</text>
  <text x="1200" y="1196" text-anchor="middle" fill="#90CAF9" font-size="14">Segment: production | isolate-attachments: false | Routes distributed automatically</text>

  <!-- East CNE box -->
  <rect x="80" y="1215" width="480" height="140" rx="6" fill="#283593" stroke="#90CAF9" stroke-width="1.5"/>
  <text x="320" y="1242" text-anchor="middle" fill="#FFFFFF" font-size="16" font-weight="bold">Core Network Edge — us-east-1</text>
  <text x="320" y="1264" text-anchor="middle" fill="#90CAF9" font-size="14">ASN ${CNE_ASN_EAST}</text>
  <text x="320" y="1286" text-anchor="middle" fill="#BBDEFB" font-size="13">Primary peer: ${EAST_FGT_PRI_P2} → ${EAST_CNE_BGP_PRI}</text>
  <text x="320" y="1306" text-anchor="middle" fill="#BBDEFB" font-size="13">Secondary peer: ${EAST_FGT_SEC_P2} → ${EAST_CNE_BGP_SEC}</text>
  <text x="320" y="1326" text-anchor="middle" fill="#BBDEFB" font-size="13">Advertises: ${WEST_SPOKE_A_CIDR}, ${WEST_SPOKE_B_CIDR}</text>
  <text x="320" y="1344" text-anchor="middle" fill="#90EE90" font-size="12">Receives: ${EAST_SPOKE_A_CIDR}, ${EAST_SPOKE_B_CIDR} (from west)</text>

  <!-- Cloud WAN middle label -->
  <text x="1200" y="1280" text-anchor="middle" fill="#90CAF9" font-size="14" font-style="italic">AWS Global Network — routes distributed via BGP across backbone</text>
  <line x1="560" y1="1285" x2="900" y2="1285" stroke="#90CAF9" stroke-width="1" stroke-dasharray="4,3"/>
  <line x1="1500" y1="1285" x2="1840" y2="1285" stroke="#90CAF9" stroke-width="1" stroke-dasharray="4,3"/>

  <!-- West CNE box -->
  <rect x="1840" y="1215" width="480" height="140" rx="6" fill="#BF360C" stroke="#FFCC80" stroke-width="1.5"/>
  <text x="2080" y="1242" text-anchor="middle" fill="#FFFFFF" font-size="16" font-weight="bold">Core Network Edge — us-west-2</text>
  <text x="2080" y="1264" text-anchor="middle" fill="#FFCC80" font-size="14">ASN ${CNE_ASN_WEST}</text>
  <text x="2080" y="1286" text-anchor="middle" fill="#FFE0B2" font-size="13">Primary peer: ${WEST_FGT_PRI_P2} → ${WEST_CNE_BGP_PRI}</text>
  <text x="2080" y="1306" text-anchor="middle" fill="#FFE0B2" font-size="13">Secondary peer: ${WEST_FGT_SEC_P2} → ${WEST_CNE_BGP_SEC}</text>
  <text x="2080" y="1326" text-anchor="middle" fill="#FFE0B2" font-size="13">Advertises: ${EAST_SPOKE_A_CIDR}, ${EAST_SPOKE_B_CIDR}</text>
  <text x="2080" y="1344" text-anchor="middle" fill="#90EE90" font-size="12">Receives: ${WEST_SPOKE_A_CIDR}, ${WEST_SPOKE_B_CIDR} (from east)</text>

  <!-- ── Legend ── -->
  <rect x="15" y="1392" width="2370" height="20" rx="3" fill="#E0E0E0"/>
  <text x="50"   y="1406" fill="#333333" font-size="11">— — — eBGP / Connect (NO_ENCAP, tunnel-less)</text>
  <text x="450"  y="1406" fill="#283593" font-size="11">───  VPC Attachment (direct to Cloud WAN, no TGW)</text>
  <text x="900"  y="1406" fill="#EE3124" font-size="11">■ FortiGate HA pair (FGCP active-passive)</text>
  <text x="1300" y="1406" fill="#2E7D32" font-size="11">□ Spoke VPCs (default route → Core Network ARN)</text>
  <text x="1800" y="1406" fill="#333333" font-size="11">Generated: ${TIMESTAMP}</text>

</svg>
SVGEOF

print_pass "SVG written: $SVG_FILE"

# ── Generate Markdown ───────────────────────────────────────────────────────
print_section "GENERATING MARKDOWN"
print_info "Output: $MD_FILE"

cat > "$MD_FILE" << MDEOF
# ${PREFIX} — Tunnelless CloudWAN Network Diagram

> **Generated:** ${TIMESTAMP}
> **Prefix:** \`${PREFIX}\` | **FGT ASN:** ${FGT_ASN} | **East CNE ASN:** ${CNE_ASN_EAST} | **West CNE ASN:** ${CNE_ASN_WEST}

---

## Architecture Overview

AWS Cloud WAN tunnel-less Connect (NO_ENCAP) with FortiGate FGCP HA pairs in two regions.
FortiGates peer directly with the Core Network Edge (CNE) via native eBGP — no GRE, no IPsec,
no tunnel inside CIDRs (169.254.x.x). Cloud WAN is the WAN fabric.

**SVG diagram:** [network_diagram.svg](network_diagram.svg)

---

## Cloud WAN

| Resource | ID |
|----------|----|
| Global Network | ${GLOBAL_NET_ID} |
| Core Network | ${CORE_NET_ID} |
| East CNE ASN | ${CNE_ASN_EAST} |
| West CNE ASN | ${CNE_ASN_WEST} |
| Segment | production (isolate-attachments: false) |

---

## VPC Summary

| VPC | Region | CIDR | ID | Attachment |
|-----|--------|------|----|------------|
| Inspection | us-east-1 | ${EAST_INSP_VPC_CIDR} | ${EAST_INSP_VPC_ID} | VPC + Connect (NO_ENCAP) |
| Spoke A | us-east-1 | ${EAST_SPOKE_A_CIDR} | ${EAST_SPOKE_A_ID} | VPC |
| Spoke B | us-east-1 | ${EAST_SPOKE_B_CIDR} | ${EAST_SPOKE_B_ID} | VPC |
| Inspection | us-west-2 | ${WEST_INSP_VPC_CIDR} | ${WEST_INSP_VPC_ID} | VPC + Connect (NO_ENCAP) |
| Spoke A | us-west-2 | ${WEST_SPOKE_A_CIDR} | ${WEST_SPOKE_A_ID} | VPC |
| Spoke B | us-west-2 | ${WEST_SPOKE_B_CIDR} | ${WEST_SPOKE_B_ID} | VPC |

---

## Inspection VPC Subnets

### us-east-1

| Subnet | AZ | CIDR |
|--------|----|------|
| Public (port1) | AZ1 | ${EAST_PUB_AZ1} |
| Public (port1) | AZ2 | ${EAST_PUB_AZ2} |
| Private (port2 / Cloud WAN) | AZ1 | ${EAST_PRIV_AZ1} |
| Private (port2 / Cloud WAN) | AZ2 | ${EAST_PRIV_AZ2} |
| HA-sync (port3 / mgmt) | AZ1 | ${EAST_HA_AZ1} |
| HA-sync (port3 / mgmt) | AZ2 | ${EAST_HA_AZ2} |

### us-west-2

| Subnet | AZ | CIDR |
|--------|----|------|
| Public (port1) | AZ1 | ${WEST_PUB_AZ1} |
| Public (port1) | AZ2 | ${WEST_PUB_AZ2} |
| Private (port2 / Cloud WAN) | AZ1 | ${WEST_PRIV_AZ1} |
| Private (port2 / Cloud WAN) | AZ2 | ${WEST_PRIV_AZ2} |
| HA-sync (port3 / mgmt) | AZ1 | ${WEST_HA_AZ1} |
| HA-sync (port3 / mgmt) | AZ2 | ${WEST_HA_AZ2} |

---

### FortiGate Instances

| Region | Instance | Instance ID | port2 IP | Cluster/Mgmt EIP |
|--------|----------|-------------|----------|------------------|
| us-east-1 | ${PREFIX}-east-fgt-primary | ${EAST_FGT_PRI_ID} | ${EAST_FGT_PRI_P2} | ${EAST_FGT_PRI_P1} / ${EAST_FGT_PRI_MGMT} |
| us-east-1 | ${PREFIX}-east-fgt-secondary | ${EAST_FGT_SEC_ID} | ${EAST_FGT_SEC_P2} | — / ${EAST_FGT_SEC_MGMT} |
| us-west-2 | ${PREFIX}-west-fgt-primary | ${WEST_FGT_PRI_ID} | ${WEST_FGT_PRI_P2} | ${WEST_FGT_PRI_P1} / ${WEST_FGT_PRI_MGMT} |
| us-west-2 | ${PREFIX}-west-fgt-secondary | ${WEST_FGT_SEC_ID} | ${WEST_FGT_SEC_P2} | — / ${WEST_FGT_SEC_MGMT} |

> port2 is the Cloud WAN BGP peer interface.

---

## BGP Configuration

### Connect Peers (NO_ENCAP — no tunnel inside CIDRs)

| Peer Name | FortiGate port2 IP | CNE BGP IP | FortiGate ASN | CNE ASN | State |
|-----------|-------------------|------------|---------------|---------|-------|
| ${PREFIX}-east-fgt-primary-peer | ${EAST_FGT_PRI_P2} | ${EAST_CNE_BGP_PRI} | ${FGT_ASN} | ${CNE_ASN_EAST} | ${EAST_PRI_PEER_STATE} |
| ${PREFIX}-east-fgt-secondary-peer | ${EAST_FGT_SEC_P2} | ${EAST_CNE_BGP_SEC} | ${FGT_ASN} | ${CNE_ASN_EAST} | ${EAST_SEC_PEER_STATE} |
| ${PREFIX}-west-fgt-primary-peer | ${WEST_FGT_PRI_P2} | ${WEST_CNE_BGP_PRI} | ${FGT_ASN} | ${CNE_ASN_WEST} | ${WEST_PRI_PEER_STATE} |
| ${PREFIX}-west-fgt-secondary-peer | ${WEST_FGT_SEC_P2} | ${WEST_CNE_BGP_SEC} | ${FGT_ASN} | ${CNE_ASN_WEST} | ${WEST_SEC_PEER_STATE} |

### Route Advertisement

| FortiGate | Advertises to CNE | Receives from CNE |
|-----------|-------------------|-------------------|
| East (both) | ${EAST_SPOKE_A_CIDR}, ${EAST_SPOKE_B_CIDR} | ${WEST_SPOKE_A_CIDR}, ${WEST_SPOKE_B_CIDR} |
| West (both) | ${WEST_SPOKE_A_CIDR}, ${WEST_SPOKE_B_CIDR} | ${EAST_SPOKE_A_CIDR}, ${EAST_SPOKE_B_CIDR} |

---

## Management Access

| Instance | Role | Management URL |
|----------|------|----------------|
| ${PREFIX}-east-fgt-primary | Active | https://${EAST_FGT_PRI_MGMT} |
| ${PREFIX}-east-fgt-secondary | Standby | https://${EAST_FGT_SEC_MGMT} |
| ${PREFIX}-west-fgt-primary | Active | https://${WEST_FGT_PRI_MGMT} |
| ${PREFIX}-west-fgt-secondary | Standby | https://${WEST_FGT_SEC_MGMT} |

---

## Verification Commands

\`\`\`bash
# FortiGate BGP session status (run on each FGT via SSH)
get router info bgp summary

# Routes received from Cloud WAN CNE
get router info bgp neighbors <cne_bgp_ip> received-routes

# Routes advertised to Cloud WAN CNE
get router info bgp neighbors <cne_bgp_ip> advertised-routes

# Full routing table
get router info routing-table all
\`\`\`

**Expected:** BGP neighbors in \`Established\` state with ${EAST_SPOKE_A_CIDR} / ${EAST_SPOKE_B_CIDR} visible on west FGTs
and ${WEST_SPOKE_A_CIDR} / ${WEST_SPOKE_B_CIDR} visible on east FGTs.

---

## Deploy

\`\`\`bash
cd ${PROJECT_DIR}
terraform apply \\
  -var="keypair_east=<your-east-keypair>" \\
  -var="keypair_west=<your-west-keypair>" \\
  -var="fortigate_admin_password=<password>" \\
  -var="ha_password=<password>"
\`\`\`

> Cloud WAN Core Network provisioning takes 10–15 minutes. Total deploy ~20–25 min.
> On first apply, spoke routes may fail with \`InvalidCoreNetworkArn.NotFound\` — run \`terraform apply\` a second time.

---

*Generated by \`scripts/generate_network_diagram.sh\` — re-run after \`terraform apply\` to refresh live IDs and IPs.*
MDEOF

print_pass "Markdown written: $MD_FILE"

echo ""
print_section "DONE"
print_info "SVG:      $SVG_FILE"
print_info "Markdown: $MD_FILE"
echo ""
