#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "power: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "power: $*" >&2; exit 1; }
help() { cat <<'EOF'
power - Power settings utility
Usage: power [status|profile [NAME]|suspend|hibernate|reboot|shutdown]
EOF
}
require_root "$@"
case "${1:-status}" in
 -h|--help) help ;;
 status) command -v upower >/dev/null 2>&1 && upower -d || true; command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get || true ;;
 profile) command -v powerprofilesctl >/dev/null 2>&1 || die "power-profiles-daemon is required."; [[ $# -eq 1 ]] && powerprofilesctl get || powerprofilesctl set "$2" ;;
 suspend) systemctl suspend ;;
 hibernate) systemctl hibernate ;;
 reboot) systemctl reboot ;;
 shutdown) systemctl poweroff ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
