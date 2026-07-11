# Linux SysDoctor 🩺

A lightweight Linux system health and security triage toolkit, built in pure Bash
with no external dependencies. Designed to answer the two questions a support
engineer gets asked most often:

1. **"Why is this server slow/broken?"** → `sysdoctor.sh`
2. **"Is someone trying to break into this server?"** → `login_watch.sh`

## Why I built this

As I prepare for support/systems roles, I wanted to practice the actual
diagnostic *process* a support engineer follows — not just memorize Linux
commands in isolation. These scripts encode a real triage workflow: check
the obvious resource bottlenecks first (disk, CPU, memory), check whether
critical services are up, check network reachability, and separately, scan
for signs of malicious access attempts.

## What's inside

### `sysdoctor.sh` — System Health Check
Runs a full diagnostic pass across disk usage, CPU load, memory usage,
network connectivity, and (optionally) a specific systemd service. When it
finds a problem — e.g. high CPU — it automatically shows the top
resource-consuming processes, because "something is wrong" is only useful
information if you can immediately see "and here's what's causing it."

```bash
./scripts/sysdoctor.sh              # run all checks
./scripts/sysdoctor.sh --disk       # just disk
./scripts/sysdoctor.sh --cpu        # just CPU
./scripts/sysdoctor.sh --mem        # just memory
./scripts/sysdoctor.sh --net        # just network
./scripts/sysdoctor.sh --service nginx   # check a specific service
```

Exit code is `0` if everything's healthy, `1` if any check found a problem —
so this script is cron/alerting-friendly out of the box.

### `login_watch.sh` — Failed Login Analyzer
Scans `/var/log/auth.log` (or any log file you point it at) for failed SSH
login attempts, groups them by source IP, and flags any IP that crosses a
configurable threshold — the standard first step in spotting a brute-force
attempt.

```bash
./scripts/login_watch.sh                       # scan default auth.log
./scripts/login_watch.sh --threshold 5          # custom threshold
./scripts/login_watch.sh --file /path/to/log    # scan a specific file
```

## Design decisions (and why)

- **Pure Bash, no dependencies.** Anyone can clone this and run it on a
  stock Ubuntu box with nothing to install. That's a deliberate constraint,
  not a limitation — support tooling needs to work on a machine that's
  already broken, not require a fresh `pip install` first.
- **Every run is logged to a timestamped file**, not just printed to the
  terminal. In a real incident, you need a paper trail of what you checked
  and when — "I looked at it earlier and it seemed fine" isn't useful
  without a timestamp.
- **`set -uo pipefail` instead of `set -e`.** I want one failed check (say,
  a missing log file) to be reported and skipped, not to silently kill the
  whole diagnostic run. A partial health report beats no health report.
- **Thresholds are configurable**, not hardcoded assumptions — because
  "80% disk usage is a problem" depends entirely on the environment.

## What I'd add next
- Config file support so thresholds don't require editing the script
- Email/Slack webhook alerting when issues are found
- A `--json` output mode for feeding results into a monitoring dashboard

## Sample output

```
[2026-07-11 08:46:33] [WARN] Disk usage HIGH on /: 87% used
[2026-07-11 08:46:33] [OK] CPU load normal: 12%
[2026-07-11 08:46:33] [WARN] Memory usage HIGH: 91% (3650MB / 4000MB)
[2026-07-11 08:46:33] [INFO] Top 5 memory-consuming processes:
    PID COMMAND         %MEM
   1842 chrome          18.2
   2011 node            14.7
...
```

## Requirements
- Bash 4+
- Standard Linux utilities (`df`, `ps`, `free`, `ping`, `systemctl`, `grep`)
  — all present by default on Ubuntu.

## License
MIT
