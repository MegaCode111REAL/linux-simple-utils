#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "system: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "system: $*" >&2; exit 1; }
help() { cat <<'EOF'
system - System information/settings utility
Usage: system [info|hostname [NAME]|uptime]
EOF
}
require_root "$@"
case "${1:-info}" in
 -h|--help) help ;;
 info) . /etc/os-release 2>/dev/null || true; echo "Hostname: $(hostname)"; echo "OS: ${PRETTY_NAME:-Linux}"; echo "Kernel: $(uname -sr)"; echo "Arch: $(uname -m)"; echo "Uptime: $(uptime -p)"; echo "CPU: $(nproc)"; free -h ;;
 hostname) [[ $# -eq 1 ]] && hostnamectl status || hostnamectl set-hostname "$2" ;;
 uptime) uptime ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
