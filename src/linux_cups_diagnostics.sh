#!/usr/bin/env bash
set -u

PRINTER_HOST=""
PORT=9100
HOURS=24
OUTPUT_DIR=""

usage() {
  echo "Usage: linux_cups_diagnostics.sh [--printer-host HOST] [--port N] [--hours N] [--output DIR]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --printer-host) PRINTER_HOST="${2:-}"; shift 2 ;;
    --port) PORT="${2:-9100}"; shift 2 ;;
    --hours) HOURS="${2:-24}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "--port must be numeric" >&2; exit 2; }
[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./cups-diagnostics-$STAMP}"
mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/cups-report.txt"
CSV="$OUTPUT_DIR/printers.csv"
JSON="$OUTPUT_DIR/summary.json"
ERRORS="$OUTPUT_DIR/command-errors.log"
: > "$REPORT"
: > "$ERRORS"
echo 'printer,device_uri,state,accepting,default' > "$CSV"

section() {
  local title="$1"
  shift
  {
    printf '\n===== %s =====\n' "$title"
    "$@"
  } >> "$REPORT" 2>> "$ERRORS" || true
}

section "Metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true; id'
section "CUPS service" bash -c 'systemctl status cups cupsd --no-pager -l 2>/dev/null || true'
section "Printers" lpstat -t
section "Devices" lpinfo -v
section "Drivers" lpinfo -m
section "Jobs" lpstat -W all -o
section "CUPS configuration" bash -c 'grep -Ev "^[[:space:]]*(#|$)" /etc/cups/cupsd.conf 2>/dev/null || true'
section "PPD inventory" bash -c 'find /etc/cups/ppd /usr/share/ppd -maxdepth 3 -type f -print 2>/dev/null | head -n 1000'
section "Recent print events" bash -c "journalctl --since '$HOURS hours ago' --no-pager 2>/dev/null | grep -Ei 'cups|printer|backend|filter failed|unable to connect' | tail -n 3000 || true"

DEFAULT_PRINTER="$(lpstat -d 2>/dev/null | sed 's/.*: //')"
while read -r _ printer _ uri; do
  printer="${printer%:}"
  state="$(lpstat -p "$printer" 2>/dev/null | head -n1)"
  accepting="$(lpstat -a "$printer" 2>/dev/null | head -n1)"
  is_default=false
  [[ "$printer" == "$DEFAULT_PRINTER" ]] && is_default=true
  printf '"%s","%s","%s","%s","%s"\n' \
    "$printer" "$uri" "${state//\"/\"\"}" "${accepting//\"/\"\"}" "$is_default" >> "$CSV"
done < <(lpstat -v 2>/dev/null)

HOST_REACHABLE=false
PORT_REACHABLE=false
if [[ -n "$PRINTER_HOST" ]]; then
  section "Printer host ping" ping -c 4 "$PRINTER_HOST"
  ping -c 1 -W 3 "$PRINTER_HOST" >/dev/null 2>&1 && HOST_REACHABLE=true

  if command -v nc >/dev/null 2>&1; then
    section "Printer TCP port test" nc -vz -w 5 "$PRINTER_HOST" "$PORT"
    nc -z -w 5 "$PRINTER_HOST" "$PORT" >/dev/null 2>&1 && PORT_REACHABLE=true
  fi
fi

CUPS_ACTIVE=false
if systemctl is-active --quiet cups 2>/dev/null || systemctl is-active --quiet cupsd 2>/dev/null; then
  CUPS_ACTIVE=true
fi

PRINTERS="$(awk 'END {print NR-1}' "$CSV")"
QUEUED_JOBS="$(lpstat -o 2>/dev/null | wc -l | tr -d ' ')"

cat > "$JSON" <<EOF
{
  "collected_at": "$(date -Is)",
  "hostname": "$(hostname -f 2>/dev/null || hostname)",
  "cups_active": $CUPS_ACTIVE,
  "printers": $PRINTERS,
  "queued_jobs": $QUEUED_JOBS,
  "default_printer": "$DEFAULT_PRINTER",
  "tested_host": "$PRINTER_HOST",
  "host_reachable": $HOST_REACHABLE,
  "port": $PORT,
  "port_reachable": $PORT_REACHABLE
}
EOF

printf '\nCUPS diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
