#!/usr/bin/env bash
set -euo pipefail

die() { echo "audio: $*" >&2; exit 1; }
help() {
    cat <<'EOF'
audio - Audio settings utility

Usage:
  audio
  audio status
  audio list
  audio outputs
  audio inputs
  audio volume [0-100]
  audio mute
  audio unmute
EOF
}

case "${1:-status}" in
    -h|--help) help ;;
esac

if command -v wpctl >/dev/null 2>&1; then
    tool=wpctl
elif command -v pactl >/dev/null 2>&1; then
    tool=pactl
else
    die "wpctl or pactl is required."
fi

case "${1:-status}" in
    status|list)
        if [[ "$tool" == wpctl ]]; then wpctl status; else pactl list short sinks; pactl list short sources; fi ;;
    outputs)
        if [[ "$tool" == wpctl ]]; then wpctl status; else pactl list short sinks; fi ;;
    inputs)
        if [[ "$tool" == wpctl ]]; then wpctl status; else pactl list short sources; fi ;;
    volume)
        if [[ "$tool" == wpctl ]]; then
            if [[ $# -eq 1 ]]; then wpctl get-volume @DEFAULT_AUDIO_SINK@; else wpctl set-volume @DEFAULT_AUDIO_SINK@ "$2%"; fi
        else
            if [[ $# -eq 1 ]]; then pactl get-sink-volume @DEFAULT_SINK@; else pactl set-sink-volume @DEFAULT_SINK@ "$2%"; fi
        fi ;;
    mute)
        if [[ "$tool" == wpctl ]]; then wpctl set-mute @DEFAULT_AUDIO_SINK@ 1; else pactl set-sink-mute @DEFAULT_SINK@ 1; fi ;;
    unmute)
        if [[ "$tool" == wpctl ]]; then wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; else pactl set-sink-mute @DEFAULT_SINK@ 0; fi ;;
    -h|--help) ;;
    *) die "Unknown command: $1 (use --help)" ;;
esac
