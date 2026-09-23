#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "display: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "display: $*" >&2; exit 1; }
help() { cat <<'EOF'
display - Display settings utility
Usage: display [list|status|modes NAME|off NAME|on NAME]
Uses xrandr when available.
EOF
}
require_root "$@"
command -v xrandr >/dev/null 2>&1 || die "xrandr is required."
case "${1:-list}" in
 -h|--help) help ;;
 list|status) xrandr --query ;;
 modes) [[ $# -ge 2 ]] || die "Usage: display modes NAME"; xrandr --query | awk -v n="$2" '$1==n {p=1; print; next} p && /^[^ ]/ {exit} p {print}' ;;
 off) [[ $# -ge 2 ]] || die "Usage: display off NAME"; xrandr --output "$2" --off ;;
 on) [[ $# -ge 2 ]] || die "Usage: display on NAME"; xrandr --output "$2" --auto ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
