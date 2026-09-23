#!/usr/bin/env bash
set -euo pipefail

require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || { echo "audio: sudo is required." >&2; exit 1; }
        exec sudo -- "$(readlink -f "$0")" "$@"
    fi
}
die() { echo "audio: $*" >&2; exit 1; }
help() { cat <<'EOF'
audio - Audio settings utility
Usage: audio [status|list|outputs|inputs|volume [0-100]|mute|unmute]
EOF
}
require_root "$@"
if command -v wpctl >/dev/null 2>&1; then tool=wpctl
elif command -v pactl >/dev/null 2>&1; then tool=pactl
else die "wpctl or pactl is required."; fi
case "${1:-status}" in
 -h|--help) help ;;
 status|list) [[ "$tool" == wpctl ]] && wpctl status || { pactl list short sinks; pactl list short sources; } ;;
 outputs) [[ "$tool" == wpctl ]] && wpctl status || pactl list short sinks ;;
 inputs) [[ "$tool" == wpctl ]] && wpctl status || pactl list short sources ;;
 volume) if [[ "$tool" == wpctl ]]; then [[ $# -eq 1 ]] && wpctl get-volume @DEFAULT_AUDIO_SINK@ || wpctl set-volume @DEFAULT_AUDIO_SINK@ "$2%"; else [[ $# -eq 1 ]] && pactl get-sink-volume @DEFAULT_SINK@ || pactl set-sink-volume @DEFAULT_SINK@ "$2%"; fi ;;
 mute) [[ "$tool" == wpctl ]] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1 || pactl set-sink-mute @DEFAULT_SINK@ 1 ;;
 unmute) [[ "$tool" == wpctl ]] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 || pactl set-sink-mute @DEFAULT_SINK@ 0 ;;
 *) die "Unknown command: $1 (use --help)" ;;
esac
