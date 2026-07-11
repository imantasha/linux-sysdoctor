#!/bin/bash
#
# login_watch.sh — Failed Login Attempt Analyzer
#
# WHY THIS EXISTS:
# One of the most common real support tickets is "is someone trying to
# break into this server?" This script scans the system auth log,
# counts failed SSH login attempts per IP address, and flags any IP
# that crosses a threshold — a classic first step in spotting a
# brute-force attack.
#
# USAGE:
#   ./login_watch.sh                 -> scan default auth log
#   ./login_watch.sh --file <path>   -> scan a specific log file
#   ./login_watch.sh --threshold 5   -> flag IPs with 5+ failed attempts
#
# NOTE: On Debian/Ubuntu the log is /var/log/auth.log
#       On RHEL/CentOS it's /var/log/secure — this script defaults to
#       the Ubuntu path since that's the target environment here.

set -uo pipefail

AUTH_LOG="/var/log/auth.log"
THRESHOLD=3
LOGFILE="$(dirname "$0")/../logs/login_watch_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# ---- parse arguments ----
while [ $# -gt 0 ]; do
    case "$1" in
        --file)      AUTH_LOG="$2"; shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 2 ;;
    esac
done

mkdir -p "$(dirname "$LOGFILE")"

if [ ! -f "$AUTH_LOG" ]; then
    log "ERROR: Log file not found at $AUTH_LOG"
    log "TIP: On this system, try running with sudo, or point at a test file with --file"
    exit 1
fi

if [ ! -r "$AUTH_LOG" ]; then
    log "ERROR: No permission to read $AUTH_LOG — try: sudo ./login_watch.sh"
    exit 1
fi

log "Scanning $AUTH_LOG for failed SSH login attempts (threshold: $THRESHOLD)..."

# THE CORE LOGIC, explained piece by piece:
#   grep "Failed password"   -> pull only failed-login lines from the log
#   grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}'  -> extract just the IP address
#                                              using a regex pattern
#   sort | uniq -c            -> count how many times each IP appears
#   sort -rn                  -> put the highest-offending IP first
RESULTS=$(grep "Failed password" "$AUTH_LOG" 2>/dev/null \
    | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | sort | uniq -c | sort -rn)

if [ -z "$RESULTS" ]; then
    log "No failed login attempts found. Clean log."
    exit 0
fi

FLAGGED=0
echo "$RESULTS" | while read -r count ip; do
    if [ "$count" -ge "$THRESHOLD" ]; then
        log "FLAGGED: $ip had $count failed login attempts — possible brute-force"
        FLAGGED=1
    else
        log "info: $ip had $count failed attempt(s) — within normal range"
    fi
done

log "Scan complete. Full results saved to $LOGFILE"
