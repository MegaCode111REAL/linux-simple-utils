#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "network: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "network: $*" >&2; exit 1; }
help() { cat <<'EOF'
network - Network settings utility
Usage: network [status|on|off|list|connections|up NAME|down NAME|wifi]
EOF
}
require_root "$@"
if command -v nmcli >/dev/null 2>&1; then backend=nmcli; else backend=ip; fi
case "${1:-status}" in
 -h|--help) help ;;
 status) [[ "$backend" == nmcli ]] && nmcli general status || ip -br link ;;
 on) [[ "$backend" == nmcli ]] || die "NetworkManager is required."; nmcli networking on ;;
 off) [[ "$backend" == nmcli ]] || die "NetworkManager is required."; nmcli networking off ;;
 list) ip -br addr ;;
 connections) [[ "$backend" == nmcli ]] || die "NetworkManager is required."; nmcli connection show ;;
 up) [[ $# -ge 2 ]] || die "Usage: network up NAME"; [[ "$backend" == nmcli ]] || die "NetworkManager is required."; nmcli connection up "$2" ;;
 down) [[ $# -ge 2 ]] || die "Usage: network down NAME"; [[ "$backend" == nmcli ]] || die "NetworkManager is required."; nmcli connection down "$2" ;;
 wifi) [[ "$backend" == nmcli ]] && nmcli radio wifi || true ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
