#!/usr/bin/env bash
set -u

RESTART_CUPS=false
PRINTER=""
ENABLE_PRINTER=false
RESUME_PRINTER=false
PURGE_JOBS=false
CANCEL_JOB=""
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage(){ cat <<'EOF'
Usage: linux_cups_repair.sh [options]

  --restart-cups           Restart and verify the CUPS service.
  --printer NAME           Select a configured printer queue.
  --enable-printer         Enable the selected printer.
  --resume-printer         Accept jobs and resume the selected printer.
  --purge-jobs             Cancel all jobs on the selected printer.
  --cancel-job ID          Cancel one selected print job.
  --dry-run                Show commands without changing printing state.
  --yes                    Skip confirmation prompts.
  --output DIR             Save logs and before/after evidence in DIR.
EOF
}
while [ "$#" -gt 0 ]; do case "$1" in
  --restart-cups) RESTART_CUPS=true; shift;; --printer) PRINTER="${2:-}"; shift 2;;
  --enable-printer) ENABLE_PRINTER=true; shift;; --resume-printer) RESUME_PRINTER=true; shift;;
  --purge-jobs) PURGE_JOBS=true; shift;; --cancel-job) CANCEL_JOB="${2:-}"; shift 2;;
  --dry-run) DRY_RUN=true; shift;; --yes) ASSUME_YES=true; shift;;
  --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;;
  *) echo "Unknown argument: $1" >&2; usage; exit 2;; esac; done
if ! $RESTART_CUPS && ! $ENABLE_PRINTER && ! $RESUME_PRINTER && ! $PURGE_JOBS && [ -z "$CANCEL_JOB" ]; then echo "Choose at least one repair action." >&2; exit 2; fi
command -v lpstat >/dev/null 2>&1 || { echo "CUPS client tools are required." >&2; exit 3; }
if $ENABLE_PRINTER || $RESUME_PRINTER || $PURGE_JOBS; then [ -n "$PRINTER" ] || { echo "--printer is required." >&2; exit 2; }; lpstat -p "$PRINTER" >/dev/null 2>&1 || { echo "Printer not found: $PRINTER" >&2; exit 2; }; fi
if [ -n "$CANCEL_JOB" ]; then case "$CANCEL_JOB" in *[!A-Za-z0-9._-]*|'') echo "Invalid job ID." >&2; exit 2;; esac; fi
SERVICE=""; for u in cups.service cupsd.service; do systemctl list-unit-files "$u" >/dev/null 2>&1 && { SERVICE="$u"; break; }; done
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./cups-repair-$STAMP}"; mkdir -p "$OUTPUT_DIR"; LOG="$OUTPUT_DIR/repair.log"; BEFORE="$OUTPUT_DIR/before.txt"; AFTER="$OUTPUT_DIR/after.txt"; : >"$LOG"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
confirm(){ $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
run(){ local d="$1"; shift; ACTIONS=$((ACTIONS+1)); log "$d"; if $DRY_RUN; then
    { printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\n'; } >>"$LOG"
    return 0
  fi; if "$@" >>"$LOG" 2>&1; then log "SUCCESS: $d"; else FAILURES=$((FAILURES+1)); log "WARNING: $d failed"; return 1; fi; }
root(){ local d="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run "$d" "$@"; else run "$d" sudo "$@"; fi; }
collect(){ local f="$1"; { echo "Collected: $(date -Is)"; if [ -n "$SERVICE" ]; then systemctl status "$SERVICE" --no-pager -l 2>&1 || true; fi; echo; lpstat -t 2>&1 || true; echo; lpq -a 2>&1 || true; echo; journalctl -u "${SERVICE:-cups.service}" -n 100 --no-pager 2>&1 || true; } >"$f"; }
collect "$BEFORE"; confirm "Apply the selected CUPS and printer repairs?" || { log "Repair cancelled."; exit 10; }
if $RESTART_CUPS; then
  if [ -n "$SERVICE" ]; then
    root "Restarting $SERVICE" systemctl restart "$SERVICE" || true
  else
    FAILURES=$((FAILURES+1)); log "WARNING: CUPS service not found."
  fi
fi
if $ENABLE_PRINTER; then
  root "Enabling printer $PRINTER" cupsenable "$PRINTER" || true
fi
if $RESUME_PRINTER; then root "Accepting jobs for $PRINTER" cupsaccept "$PRINTER" || true; root "Resuming printer $PRINTER" cupsenable "$PRINTER" || true; fi
if $PURGE_JOBS && confirm "Cancel all jobs on $PRINTER?"; then root "Cancelling all jobs on $PRINTER" cancel -a "$PRINTER" || true; fi
[ -z "$CANCEL_JOB" ] || root "Cancelling print job $CANCEL_JOB" cancel "$CANCEL_JOB" || true
$DRY_RUN || sleep 2; collect "$AFTER"; if $RESTART_CUPS && [ -n "$SERVICE" ]; then systemctl is-active --quiet "$SERVICE" || { FAILURES=$((FAILURES+1)); log "WARNING: CUPS service is not active."; }; fi; [ "$FAILURES" -eq 0 ] || exit 20; log "Print repair completed successfully. Actions performed: $ACTIONS"
