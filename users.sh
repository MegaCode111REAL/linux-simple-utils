#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "users: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "users: $*" >&2; exit 1; }
help() { cat <<'EOF'
users - User/account settings utility
Usage: users [list|current|groups NAME|add NAME|delete NAME]
EOF
}
require_root "$@"
case "${1:-list}" in
 -h|--help) help ;;
 list) awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd ;;
 current) who ;;
 groups) [[ $# -ge 2 ]] || die "Usage: users groups NAME"; id "$2" ;;
 add) [[ $# -ge 2 ]] || die "Usage: users add NAME"; useradd -m "$2" ;;
 delete) [[ $# -ge 2 ]] || die "Usage: users delete NAME"; userdel -r "$2" ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
