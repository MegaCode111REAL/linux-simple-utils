#!/usr/bin/env bash
set -euo pipefail

die() { echo "display: $*" >&2; exit 1; }
help() {
    cat <<'EOF'
display - Display settings utility

Usage:
  display
  display list
  display status
  display modes NAME
  display off NAME
  display on NAME

Uses xrandr when available. Wayland compositors may require their own tools.
EOF
}

case "${1:-list}" in
    -h|--help) help; exit 0 ;;
esac

command -v xrandr >/dev/null 2>&1 || die "xrandr is required."

case "${1:-list}" in
    list|status) xrandr --query ;;
    modes)
        [[ $# -ge 2 ]] || die "Usage: display modes NAME"
        xrandr --query | awk -v n="$2" '$1==n {p=1; print; next} p && /^[^ ]/ {exit} p {print}' ;;
    off)
        [[ $# -ge 2 ]] || die "Usage: display off NAME"
        xrandr --output "$2" --off ;;
    on)
        [[ $# -ge 2 ]] || die "Usage: display on NAME"
        xrandr --output "$2" --auto ;;
    *) die "Unknown command: $1 (use --help)" ;;
esac
