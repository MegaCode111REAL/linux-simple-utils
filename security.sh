#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "security: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "security: $*" >&2; exit 1; }
help() { cat <<'EOF'
security - Security settings utility
Usage: security [status|firewall [status|on|off]|ssh [status|on|off]]
EOF
}
require_root "$@"
case "${1:-status}" in
 -h|--help) help ;;
 status) echo "Firewall:"; if command -v ufw >/dev/null 2>&1; then ufw status; elif command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --state; else echo "No UFW/firewalld detected."; fi; echo; echo "SSH:"; systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo "inactive/not installed" ;;
 firewall) action="${2:-status}"; if command -v ufw >/dev/null 2>&1; then case "$action" in status) ufw status verbose;; on) ufw --force enable;; off) ufw disable;; *) die "Use firewall status|on|off";; esac; elif command -v firewall-cmd >/dev/null 2>&1; then case "$action" in status) firewall-cmd --state; firewall-cmd --list-all;; on) systemctl enable --now firewalld;; off) systemctl disable --now firewalld;; *) die "Use firewall status|on|off";; esac; else die "Neither ufw nor firewalld is installed."; fi ;;
 ssh) action="${2:-status}"; case "$action" in status) systemctl status ssh --no-pager 2>/dev/null || systemctl status sshd --no-pager;; on) systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd;; off) systemctl disable --now ssh 2>/dev/null || systemctl disable --now sshd;; *) die "Use ssh status|on|off";; esac ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
