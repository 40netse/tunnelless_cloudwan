#!/usr/bin/env bash
# Destroy tunnelless_cloudwan and clean up generated artefacts.
# Re-authenticate with AWS SSO before running if your session has expired.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")"
STATE_FILE="${TF_DIR}/.deploy_state.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Load log/report paths from the deploy run; fall back to new files if missing
if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
    echo -e "${BLUE}Continuing deploy run: ${REPORT_FILE}${NC}"
else
    TS=$(date +%Y%m%d_%H%M%S)
    REPORT_FILE="${TF_DIR}/deploy_report_${TS}.txt"
    LOG_FILE="${TF_DIR}/deploy_log_${TS}.txt"
    echo -e "${YELLOW}No deploy state found — logging to new files${NC}"
fi

log()  { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

now()     { date +%s; }
elapsed() { local d=$(( $2 - $1 )); printf "%dm %ds" $(( d/60 )) $(( d%60 )); }

TEARDOWN_START=$(now)

# ── Credentials check ──────────────────────────────────────────────────────────
log "━━━ PRE-FLIGHT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
aws sts get-caller-identity > /dev/null 2>&1 || die "AWS credentials invalid — run: aws sso login (or export AWS_PROFILE)"
ok "AWS credentials valid"

# ── Destroy ────────────────────────────────────────────────────────────────────
# Cloud WAN attachment deletion can take several minutes per attachment (6 total).
# The provider handles retries automatically; just let it run.
log "━━━ TERRAFORM DESTROY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Note: Cloud WAN attachment deletions can take several minutes each."
DESTROY_START=$(now)
cd "$TF_DIR"
terraform destroy -auto-approve 2>&1 | tee -a "$LOG_FILE"
DESTROY_RC=${PIPESTATUS[0]}
DESTROY_END=$(now)

if [[ $DESTROY_RC -ne 0 ]]; then
    warn "terraform destroy exited $DESTROY_RC — check log: $LOG_FILE"
else
    ok "Terraform destroy complete ($(elapsed $DESTROY_START $DESTROY_END))"
fi

# ── Clean up generated artefacts ───────────────────────────────────────────────
log "━━━ CLEANUP ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Network diagram files — regenerated fresh after each deploy
for f in "${TF_DIR}/network_diagram.svg" "${TF_DIR}/network_diagram.md"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        ok "Removed: $(basename $f)"
    fi
done

# Terraform plan file if left behind
rm -f "${TF_DIR}/tfplan"
ok "Cleanup complete"

TEARDOWN_END=$(now)

# ── Append teardown summary to the original report ────────────────────────────
cat >> "$REPORT_FILE" << SUMMARY

================================================================================
  TEARDOWN COMPLETE  —  $(date)
  Destroy time : $(elapsed $DESTROY_START $DESTROY_END)
  Total        : $(elapsed $TEARDOWN_START $TEARDOWN_END)
================================================================================
SUMMARY

# Remove state file — deploy is now fully torn down
rm -f "$STATE_FILE"
ok "Deploy state file removed"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Teardown complete. Report: ${REPORT_FILE}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
