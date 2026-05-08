#!/usr/bin/env bash
# Deploy tunnelless_cloudwan — init → apply (pass 1) → apply (pass 2 for route timing) → diagram → report
# Run teardown.sh to destroy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")"
TS=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${TF_DIR}/deploy_report_${TS}.txt"
LOG_FILE="${TF_DIR}/deploy_log_${TS}.txt"
STATE_FILE="${TF_DIR}/.deploy_state.env"
DIAGRAM_SCRIPT="${SCRIPT_DIR}/generate_network_diagram.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

now()     { date +%s; }
elapsed() { local d=$(( $2 - $1 )); printf "%dm %ds" $(( d/60 )) $(( d%60 )); }

run_tf() {
    local label="$1"; shift
    log "$label: $*"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local rc=${PIPESTATUS[0]}
    [[ $rc -eq 0 ]] || die "$label failed (exit $rc)"
}

tf_output() {
    local key="$1"
    cd "$TF_DIR"
    terraform output -raw "$key" 2>/dev/null || echo "—"
}

tf_output_json_val() {
    local key="$1" json="$2"
    echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
v = d.get('${key}', {}).get('value', '')
if isinstance(v, dict): v = list(v.values())[0] if v else ''
print(v if v else '—')
" 2>/dev/null || echo "—"
}

DEPLOY_START=$(now)

# ── Pre-flight ────────────────────────────────────────────────────────────────
log "━━━ PRE-FLIGHT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
PREFLIGHT_START=$(now)

CALLER_OUT=$(aws sts get-caller-identity 2>&1) || {
    echo "$CALLER_OUT" | tee -a "$LOG_FILE"
    die "AWS credentials invalid — run: aws_login (or aws sso login / export AWS_PROFILE)"
}
ok "AWS credentials valid — $(echo "$CALLER_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Account','?'), d.get('Arn','?'))" 2>/dev/null || echo "$CALLER_OUT")"

[[ -f "${TF_DIR}/terraform.tfvars" ]] || die "terraform.tfvars not found in $TF_DIR"
ok "terraform.tfvars found"

for cmd in terraform aws jq python3; do
    command -v "$cmd" &>/dev/null || die "$cmd not found"
done
ok "Required tools present (terraform, aws, jq, python3)"

PREFLIGHT_END=$(now)
ok "Pre-flight complete ($(elapsed $PREFLIGHT_START $PREFLIGHT_END))"

# ── Init ──────────────────────────────────────────────────────────────────────
log "━━━ INIT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
INIT_START=$(now)
cd "$TF_DIR"
run_tf "init" terraform init -upgrade
INIT_END=$(now)
ok "Init complete ($(elapsed $INIT_START $INIT_END))"

# ── Apply — pass 1 ────────────────────────────────────────────────────────────
# Cloud WAN Core Network provisioning takes 10–15 min.
# Spoke VPC routes may fail with InvalidCoreNetworkArn.NotFound on the first pass
# if VPC attachments haven't reached AVAILABLE yet — pass 2 fixes that.
log "━━━ APPLY PASS 1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Note: Cloud WAN Core Network provisioning takes ~10–15 minutes."
APPLY1_START=$(now)
terraform apply -auto-approve 2>&1 | tee -a "$LOG_FILE"
APPLY1_RC=${PIPESTATUS[0]}
APPLY1_END=$(now)
if [[ $APPLY1_RC -ne 0 ]]; then
    warn "Apply pass 1 had errors ($(elapsed $APPLY1_START $APPLY1_END)) — expected InvalidCoreNetworkArn.NotFound on routes; pass 2 converges"
else
    ok "Apply pass 1 complete ($(elapsed $APPLY1_START $APPLY1_END))"
fi

# ── Apply — pass 2 ────────────────────────────────────────────────────────────
# Spoke VPC routes (0.0.0.0/0 → core_network_arn) sometimes fail on pass 1 if
# attachments were still pending AVAILABLE. Pass 2 is always fast (idempotent
# except for any missing routes) and ensures the deployment is fully converged.
log "━━━ APPLY PASS 2 (route convergence) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
APPLY2_START=$(now)
run_tf "apply pass 2" terraform apply -auto-approve
APPLY2_END=$(now)
ok "Apply pass 2 complete ($(elapsed $APPLY2_START $APPLY2_END))"

# ── Capture outputs ────────────────────────────────────────────────────────────
log "━━━ CAPTURING OUTPUTS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
OUTPUTS_START=$(now)
cd "$TF_DIR"
TF_OUTPUTS=$(terraform output -json 2>>"$LOG_FILE" || echo "{}")

CORE_NET_ID=$(tf_output "core_network_id")
CORE_NET_ARN=$(tf_output "core_network_arn")

EAST_PRI_MGMT=$(tf_output "east_primary_mgmt_url")
EAST_SEC_MGMT=$(tf_output "east_secondary_mgmt_url")
EAST_PRI_P2=$(tf_output   "east_primary_port2_ip")
EAST_SEC_P2=$(tf_output   "east_secondary_port2_ip")

WEST_PRI_MGMT=$(tf_output "west_primary_mgmt_url")
WEST_SEC_MGMT=$(tf_output "west_secondary_mgmt_url")
WEST_PRI_P2=$(tf_output   "west_primary_port2_ip")
WEST_SEC_P2=$(tf_output   "west_secondary_port2_ip")

EAST_PRI_PEER=$(tf_output "east_connect_peer_primary_id")
EAST_SEC_PEER=$(tf_output "east_connect_peer_secondary_id")
WEST_PRI_PEER=$(tf_output "west_connect_peer_primary_id")
WEST_SEC_PEER=$(tf_output "west_connect_peer_secondary_id")

OUTPUTS_END=$(now)
ok "Outputs captured ($(elapsed $OUTPUTS_START $OUTPUTS_END))"
ok "Core Network: $CORE_NET_ID"
ok "East primary:   $EAST_PRI_MGMT"
ok "East secondary: $EAST_SEC_MGMT"
ok "West primary:   $WEST_PRI_MGMT"
ok "West secondary: $WEST_SEC_MGMT"

# ── Network diagram ────────────────────────────────────────────────────────────
log "━━━ NETWORK DIAGRAM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
DIAGRAM_START=$(now)
if [[ -x "$DIAGRAM_SCRIPT" ]]; then
    bash "$DIAGRAM_SCRIPT" 2>&1 | tee -a "$LOG_FILE" && true \
        || warn "Network diagram generation failed (non-fatal)"
else
    warn "generate_network_diagram.sh not found or not executable — skipping"
fi
DIAGRAM_END=$(now)
ok "Network diagram complete ($(elapsed $DIAGRAM_START $DIAGRAM_END))"

# ── Build report ───────────────────────────────────────────────────────────────
log "━━━ DEPLOY REPORT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
REPORT_START=$(now)

cat > "$REPORT_FILE" << REPORT
================================================================================
  TUNNELLESS CLOUDWAN — DEPLOY REPORT
  $(date)
================================================================================

── Cloud WAN ────────────────────────────────────────────────────────────────────
  Core Network ID  : ${CORE_NET_ID}
  Core Network ARN : ${CORE_NET_ARN}

── us-east-1 FortiGates ─────────────────────────────────────────────────────────
  Primary   mgmt : ${EAST_PRI_MGMT}
  Primary   p2   : ${EAST_PRI_P2}  (BGP peer)
  Primary   peer : ${EAST_PRI_PEER}
  Secondary mgmt : ${EAST_SEC_MGMT}
  Secondary p2   : ${EAST_SEC_P2}  (BGP peer)
  Secondary peer : ${EAST_SEC_PEER}

── us-west-2 FortiGates ─────────────────────────────────────────────────────────
  Primary   mgmt : ${WEST_PRI_MGMT}
  Primary   p2   : ${WEST_PRI_P2}  (BGP peer)
  Primary   peer : ${WEST_PRI_PEER}
  Secondary mgmt : ${WEST_SEC_MGMT}
  Secondary p2   : ${WEST_SEC_P2}  (BGP peer)
  Secondary peer : ${WEST_SEC_PEER}

── BGP verification (run on each FortiGate via SSH) ─────────────────────────────
  get router info bgp summary
  get router info bgp neighbors <cne_bgp_ip> received-routes
  get router info bgp neighbors <cne_bgp_ip> advertised-routes

── Network Diagram ───────────────────────────────────────────────────────────────
  SVG  : ${TF_DIR}/network_diagram.svg
  Docs : ${TF_DIR}/network_diagram.md

── Timing ────────────────────────────────────────────────────────────────────────
  Pre-flight    : $(elapsed $PREFLIGHT_START $PREFLIGHT_END)
  Init          : $(elapsed $INIT_START $INIT_END)
  Apply pass 1  : $(elapsed $APPLY1_START $APPLY1_END)
  Apply pass 2  : $(elapsed $APPLY2_START $APPLY2_END)
  Output capture: $(elapsed $OUTPUTS_START $OUTPUTS_END)
  Diagram       : $(elapsed $DIAGRAM_START $DIAGRAM_END)
  Report build  : $(elapsed $REPORT_START $REPORT_END)
  ──────────────────────────────────────────
  TOTAL         : $(elapsed $DEPLOY_START $REPORT_END)

================================================================================
  DEPLOY COMPLETE  —  $(date)
  Re-authenticate if needed, then run: bash scripts/teardown.sh
================================================================================
REPORT

REPORT_END=$(now)
ok "Report complete ($(elapsed $REPORT_START $REPORT_END))"

cat "$REPORT_FILE" | tee -a "$LOG_FILE"

# Save state for teardown.sh
cat > "$STATE_FILE" << STATE
REPORT_FILE="${REPORT_FILE}"
LOG_FILE="${LOG_FILE}"
STATE

ok "State saved to ${STATE_FILE}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Deploy complete. Re-authenticate if needed, then: bash scripts/teardown.sh${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
