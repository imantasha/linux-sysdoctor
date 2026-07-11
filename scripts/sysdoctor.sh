#!/bin/bash
#
# sysdoctor.sh — Linux System Health Diagnostic Tool
#
# WHY THIS EXISTS:
# When a server "feels slow" or a user files a vague ticket, a support
# engineer's first job is to systematically rule things out — disk, CPU,
# memory, services, network — instead of guessing. This script automates
# that first-pass triage so nothing gets missed under pressure.
#
# USAGE:
#   ./sysdoctor.sh            -> run all checks, print + log results
#   ./sysdoctor.sh --disk     -> run only the disk check
#   ./sysdoctor.sh --cpu      -> run only the CPU check
#   ./sysdoctor.sh --mem      -> run only the memory check
#   ./sysdoctor.sh --service <name>  -> check a specific service's status
#   ./sysdoctor.sh --net      -> run only the network check
#
# EXIT CODES:
#   0 = all checks passed / no problems found
#   1 = at least one check found a problem (useful for cron/alerting)

set -uo pipefail   # treat unset vars as errors, catch failures in pipelines
# (intentionally NOT using 'set -e' here — one failed check should not
#  kill the whole script; we want to keep running remaining checks)

LOGFILE="$(dirname "$0")/../logs/sysdoctor_$(date +%Y%m%d_%H%M%S).log"
ISSUES_FOUND=0

# Thresholds — the numbers that decide "fine" vs "flag it".
# In a real environment these would come from a config file so ops teams
# can tune them without touching code. Hardcoded here for simplicity.
DISK_THRESHOLD=80      # percent used
CPU_THRESHOLD=85        # percent load
MEM_THRESHOLD=85        # percent used

# ---- helper: log to both terminal and logfile, with a timestamp ----
log() {
    local level="$1"
    shift
    local msg="$*"
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg"
    echo "$line" | tee -a "$LOGFILE"
}

# ---- CHECK 1: Disk usage ----
check_disk() {
    log "INFO" "Checking disk usage (threshold: ${DISK_THRESHOLD}%)..."
    # df -h --output gives us clean columns instead of parsing raw df output
    # tail -n +2 skips the header row
    while read -r usage mount; do
        pct="${usage%\%}"   # strip the % sign to compare numerically
        if [ "$pct" -ge "$DISK_THRESHOLD" ]; then
            log "WARN" "Disk usage HIGH on $mount: ${pct}% used"
            ISSUES_FOUND=1
        else
            log "OK" "Disk usage normal on $mount: ${pct}% used"
        fi
    done < <(df -h --output=pcent,target | tail -n +2)
}

# ---- CHECK 2: CPU load ----
check_cpu() {
    log "INFO" "Checking CPU load (threshold: ${CPU_THRESHOLD}%)..."
    # /proc/loadavg gives 1/5/15 min load averages. We compare the 1-min
    # average against number of CPU cores to get a rough load percentage.
    local cores
    cores=$(nproc)
    local load1
    load1=$(awk '{print $1}' /proc/loadavg)
    # awk does the float math bash can't do natively
    local load_pct
    load_pct=$(awk -v l="$load1" -v c="$cores" 'BEGIN{printf "%.0f", (l/c)*100}')

    if [ "$load_pct" -ge "$CPU_THRESHOLD" ]; then
        log "WARN" "CPU load HIGH: ${load_pct}% (1-min avg: $load1 across $cores cores)"
        ISSUES_FOUND=1
        # if CPU is high, immediately show WHO is responsible — this is
        # the actual troubleshooting step a TSE takes next
        log "INFO" "Top 5 CPU-consuming processes:"
        ps -eo pid,comm,%cpu --sort=-%cpu | head -6 | tee -a "$LOGFILE"
    else
        log "OK" "CPU load normal: ${load_pct}%"
    fi
}

# ---- CHECK 3: Memory usage ----
check_mem() {
    log "INFO" "Checking memory usage (threshold: ${MEM_THRESHOLD}%)..."
    # free -m gives memory in MB; we calculate used-as-percent-of-total
    local total used pct
    read -r total used <<< "$(free -m | awk '/^Mem:/{print $2, $3}')"
    pct=$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.0f", (u/t)*100}')

    if [ "$pct" -ge "$MEM_THRESHOLD" ]; then
        log "WARN" "Memory usage HIGH: ${pct}% (${used}MB / ${total}MB)"
        ISSUES_FOUND=1
        log "INFO" "Top 5 memory-consuming processes:"
        ps -eo pid,comm,%mem --sort=-%mem | head -6 | tee -a "$LOGFILE"
    else
        log "OK" "Memory usage normal: ${pct}% (${used}MB / ${total}MB)"
    fi
}

# ---- CHECK 4: Specific service status ----
check_service() {
    local svc="$1"
    log "INFO" "Checking service: $svc..."
    if ! command -v systemctl &> /dev/null; then
        log "ERROR" "systemctl not available on this system (are you in a container without systemd?)"
        ISSUES_FOUND=1
        return
    fi
    if systemctl is-active --quiet "$svc"; then
        log "OK" "Service '$svc' is running"
    else
        log "WARN" "Service '$svc' is NOT running"
        ISSUES_FOUND=1
        log "INFO" "Last 5 log lines for $svc:"
        journalctl -u "$svc" -n 5 --no-pager 2>/dev/null | tee -a "$LOGFILE" || log "INFO" "No journal logs available"
    fi
}

# ---- CHECK 5: Basic network reachability ----
check_net() {
    log "INFO" "Checking network connectivity..."
    # -c 2 = send only 2 pings, -W 2 = wait max 2 sec per reply
    # We test against a DNS resolver IP (8.8.8.8) to separate
    # "internet is down" from "DNS is down" — a classic real triage split
    if ping -c 2 -W 2 8.8.8.8 &> /dev/null; then
        log "OK" "Internet connectivity (IP-level) is working"
    else
        log "WARN" "Cannot reach 8.8.8.8 — possible network outage"
        ISSUES_FOUND=1
    fi

    if ping -c 2 -W 2 google.com &> /dev/null; then
        log "OK" "DNS resolution is working"
    else
        log "WARN" "Cannot resolve google.com — possible DNS issue (even if IP connectivity works)"
        ISSUES_FOUND=1
    fi
}

# ---- main: parse arguments and decide what to run ----
main() {
    mkdir -p "$(dirname "$LOGFILE")"
    log "INFO" "=== sysdoctor.sh started ==="

    case "${1:-}" in
        --disk)    check_disk ;;
        --cpu)     check_cpu ;;
        --mem)     check_mem ;;
        --net)     check_net ;;
        --service)
            if [ -z "${2:-}" ]; then
                log "ERROR" "Usage: --service <service-name>"
                exit 2
            fi
            check_service "$2"
            ;;
        "")
            # no argument = run everything, the normal "health check" mode
            check_disk
            check_cpu
            check_mem
            check_net
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--disk|--cpu|--mem|--net|--service <name>]"
            exit 2
            ;;
    esac

    log "INFO" "=== sysdoctor.sh finished. Issues found: $ISSUES_FOUND ==="
    log "INFO" "Full log saved to: $LOGFILE"
    exit "$ISSUES_FOUND"
}

main "$@"
