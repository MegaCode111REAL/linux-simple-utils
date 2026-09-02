```bash
#!/usr/bin/env bash

# ============================================================
# wifi.sh
# Simple NetworkManager Wi-Fi controller
# Requires: nmcli
# ============================================================

set -o pipefail

# ---------- Configuration ----------

TABLE_WIDTH=42

# ---------- Helpers ----------

die() {
    echo "wifi: $*" >&2
    exit 1
}

require_nmcli() {
    command -v nmcli >/dev/null 2>&1 || die "nmcli was not found. Install NetworkManager first."
}

wifi_state() {
    nmcli -t -f WIFI general 2>/dev/null
}

is_wifi_enabled() {
    [[ "$(wifi_state)" == "enabled" ]]
}

# Escape strings containing ':' for nmcli's terse output.
# nmcli uses ':' as its field separator.
nm_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/:/\\:/g'
}

# ---------- Main display ----------

show_table() {
    local wifi_status
    wifi_status="$(wifi_state)"

    echo
    echo "┌──────────────────────────────────────────────────────────┐"
    printf "│ %-56s │\n" "Wi-Fi"
    echo "├──────────────────────────────────────────────────────────┤"

    if [[ "$wifi_status" != "enabled" ]]; then
        printf "│ %-56s │\n" "Wi-Fi: disabled"
        echo "└──────────────────────────────────────────────────────────┘"
        return
    fi

    # Get currently connected SSID.
    local connected
    connected="$(
        nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null |
        awk -F: '$1 == "yes" { print substr($0,4); exit }'
    )"

    # Known connection profiles.
    declare -A known
    while IFS= read -r ssid; do
        [[ -n "$ssid" ]] && known["$ssid"]=1
    done < <(
        nmcli -t -f TYPE,NAME connection show 2>/dev/null |
        awk -F: '$1 == "802-11-wireless" { print substr($0,20) }'
    )

    # Available networks.
    declare -A available

    while IFS= read -r line; do
        # nmcli terse output escapes ':'.
        # We only need SSID, so remove everything after the final
        # relevant fields by using awk with a cautious parser.
        local ssid
        ssid="$(printf '%s\n' "$line" | sed 's/:.*$//')"

        [[ -n "$ssid" ]] && available["$ssid"]=1
    done < <(
        nmcli -t -f SSID dev wifi list --rescan no 2>/dev/null |
        sed 's/\\:/::/g'
    )

    # A more reliable SSID list using nmcli's JSON output where available.
    # Fall back to normal terse output above.
    if command -v python3 >/dev/null 2>&1; then
        while IFS= read -r ssid; do
            [[ -n "$ssid" ]] && available["$ssid"]=1
        done < <(
            nmcli -t -f SSID dev wifi list --rescan no 2>/dev/null |
            sed 's/\\:/\x00/g' |
            tr '\0' ':' |
            sed '/^$/d'
        )
    fi

    # Build unique sorted list.
    declare -A all
    local ssid

    for ssid in "${!known[@]}"; do
        all["$ssid"]=1
    done

    for ssid in "${!available[@]}"; do
        all["$ssid"]=1
    done

    if [[ -n "$connected" ]]; then
        all["$connected"]=1
    fi

    if [[ "${#all[@]}" -eq 0 ]]; then
        printf "│ %-56s │\n" "No Wi-Fi networks found."
        echo "└──────────────────────────────────────────────────────────┘"
        return
    fi

    echo "│ Name                                                     │"
    echo "├──────────────────────────────────────────────────────────┤"

    while IFS= read -r ssid; do
        [[ -z "$ssid" ]] && continue

        local state="available"

        if [[ "$ssid" == "$connected" ]]; then
            state="connected"
        elif [[ "${known[$ssid]:-0}" == "1" ]]; then
            state="known"
        fi

        # Keep the table usable with long SSIDs.
        local display="$ssid"
        if (( ${#display} > 38 )); then
            display="${display:0:35}..."
        fi

        printf "│ %-38s │ %-14s │\n" "$display" "$state"
    done < <(printf '%s\n' "${!all[@]}" | LC_ALL=C sort -f)

    echo "└──────────────────────────────────────┴─────────────────┘"
    echo
}

# ---------- Commands ----------

connect_wifi() {
    local name="$1"

    [[ -n "$name" ]] || die "missing network name"

    if ! is_wifi_enabled; then
        echo "Wi-Fi is disabled. Enabling it..."
        nmcli radio wifi on || die "could not enable Wi-Fi"
        sleep 1
    fi

    echo "Connecting to: $name"
    echo

    # --ask makes nmcli interactively request required credentials.
    # This supports passwords and authentication supported by
    # NetworkManagers connection mechanism.
    nmcli --ask device wifi connect "$name"
}

enable_wifi() {
    if is_wifi_enabled; then
        echo "Wi-Fi is already enabled."
        return 0
    fi

    nmcli radio wifi on || die "could not enable Wi-Fi"
    echo "Wi-Fi enabled."
}

disable_wifi() {
    if ! is_wifi_enabled; then
        echo "Wi-Fi is already disabled."
        return 0
    fi

    nmcli radio wifi off || die "could not disable Wi-Fi"
    echo "Wi-Fi disabled."
}

rescan_wifi() {
    if ! is_wifi_enabled; then
        die "Wi-Fi is disabled. Use -e/--enable first."
    fi

    echo "Scanning for Wi-Fi networks..."
    nmcli device wifi rescan || die "Wi-Fi scan failed"
    echo "Scan complete."
    show_table
}

show_status() {
    echo
    echo "Wi-Fi status"
    echo "────────────"

    nmcli radio wifi

    echo
    echo "Devices"
    echo "───────"

    nmcli device status

    echo
    echo "Active connections"
    echo "──────────────────"

    nmcli connection show --active
}

show_known() {
    echo
    echo "Known Wi-Fi networks"
    echo "────────────────────"

    local found=0

    while IFS= read -r line; do
        local type name
        type="${line%%:*}"
        name="${line#*:}"

        if [[ "$type" == "802-11-wireless" ]]; then
            printf "  • %s\n" "$name"
            found=1
        fi
    done < <(
        nmcli -t -f TYPE,NAME connection show 2>/dev/null
    )

    if (( found == 0 )); then
        echo "  No known Wi-Fi networks."
    fi
}

disconnect_wifi() {
    local device

    device="$(
        nmcli -t -f DEVICE,TYPE device status 2>/dev/null |
        awk -F: '$2 == "wifi" { print $1; exit }'
    )"

    [[ -n "$device" ]] || die "no Wi-Fi device found"

    echo "Disconnecting $device..."
    nmcli device disconnect "$device" || die "could not disconnect Wi-Fi"
    echo "Disconnected."
}

show_help() {
    cat <<'EOF'

wifi.sh - Wi-Fi controller

Usage:
  wifi.sh                         Show Wi-Fi networks
  wifi.sh -c, --connect NAME      Connect to a network
  wifi.sh -e, --enable            Enable Wi-Fi
  wifi.sh -d, --disable           Disable Wi-Fi
  wifi.sh -r, --rescan            Rescan networks
  wifi.sh -s, --status            Show Wi-Fi/device status
  wifi.sh -k, --known             Show known/saved networks
  wifi.sh -x, --disconnect        Disconnect current Wi-Fi
  wifi.sh -h, --help              Show this help

Examples:
  wifi.sh
  wifi.sh --connect "My WiFi"
  wifi.sh -c "School Network"
  wifi.sh --disable
  wifi.sh -r
  wifi.sh --status

Network states:
  connected   Currently connected
  known       Saved by NetworkManager
  available   Currently visible but not saved

When connecting, NetworkManagers interactive authentication
prompt is used, so passwords and other supported credentials
are requested securely rather than being stored in this script.

EOF
}

# ---------- Argument parsing ----------

require_nmcli

if [[ $# -eq 0 ]]; then
    echo "use -h for help"
    show_table
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in

        -h|--help)
            show_help
            ;;

        -c|--connect)
            [[ $# -ge 2 ]] || die "option $1 requires a network name"
            connect_wifi "$2"
            shift
            ;;

        -e|--enable)
            enable_wifi
            ;;

        -d|--disable)
            disable_wifi
            ;;

        -r|--rescan)
            rescan_wifi
            ;;

        -s|--status)
            show_status
            ;;

        -k|--known)
            show_known
            ;;

        -x|--disconnect)
            disconnect_wifi
            ;;

        --)
            shift
            break
            ;;

        -*)
            die "unknown option: $1 (use -h for help)"
            ;;

        *)
            die "unexpected argument: $1 (use -h for help)"
            ;;

    esac

    shift
done
```
