#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "storage: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "storage: $*" >&2; exit 1; }
help() { cat <<'EOF'
storage - Storage settings utility
Usage: storage [status|disks|mounts|usage|eject DEVICE]
EOF
}
require_root "$@"
case "${1:-status}" in
 -h|--help) help ;;
 status) lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS; echo; df -hT ;;
 disks) lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS ;;
 mounts) findmnt ;;
 usage) df -hT ;;
 eject) [[ $# -ge 2 ]] || die "Usage: storage eject DEVICE"; umount "$2" 2>/dev/null || true; command -v eject >/dev/null 2>&1 && eject "$2" || true ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
