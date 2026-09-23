#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "software: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "software: $*" >&2; exit 1; }
help() { cat <<'EOF'
software - Software/package settings utility
Usage: software [updates|update|search NAME|install NAME|remove NAME]
Supports apt, dnf, pacman and zypper.
EOF
}
require_root "$@"
if command -v apt-get >/dev/null 2>&1; then pm=apt
elif command -v dnf >/dev/null 2>&1; then pm=dnf
elif command -v pacman >/dev/null 2>&1; then pm=pacman
elif command -v zypper >/dev/null 2>&1; then pm=zypper
else die "No supported package manager found."; fi
case "${1:-updates}" in
 -h|--help) help ;;
 updates) case "$pm" in apt) apt update -qq; apt list --upgradable 2>/dev/null || true;; dnf) dnf check-update || [[ $? -eq 100 ]];; pacman) pacman -Qu;; zypper) zypper list-updates;; esac ;;
 update) case "$pm" in apt) apt update && apt upgrade;; dnf) dnf upgrade;; pacman) pacman -Syu;; zypper) zypper update;; esac ;;
 search) [[ $# -ge 2 ]] || die "Usage: software search NAME"; case "$pm" in apt) apt search "$2";; dnf) dnf search "$2";; pacman) pacman -Ss "$2";; zypper) zypper search "$2";; esac ;;
 install) [[ $# -ge 2 ]] || die "Usage: software install NAME"; case "$pm" in apt) apt install "$2";; dnf) dnf install "$2";; pacman) pacman -S "$2";; zypper) zypper install "$2";; esac ;;
 remove) [[ $# -ge 2 ]] || die "Usage: software remove NAME"; case "$pm" in apt) apt remove "$2";; dnf) dnf remove "$2";; pacman) pacman -R "$2";; zypper) zypper remove "$2";; esac ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
