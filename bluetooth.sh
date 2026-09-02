#!/usr/bin/env bash

# ============================================================
# bluetooth.sh
# Simple Bluetooth controller using bluetoothctl
# Requires: BlueZ / bluetoothctl
# ============================================================

set -o pipefail

# ---------- Helpers ----------

die() {
    echo "bluetooth: $*" >&2
    exit 1
}

require_bluetoothctl() {
    command -v bluetoothctl >/dev/null 2>&1 ||
        die "bluetoothctl was not found. Install BlueZ first."
}

bt_cmd() {
    bluetoothctl "$@" 2>/dev/null
}

is_enabled() {
    bt_cmd show | grep -q "Powered: yes"
}

# ---------- Device table ----------

show_table() {
    echo
    echo "┌────────────────────────────────────────────────────────────────────────────┐"
    echo "│ Bluetooth                                                                  │"
    echo "├────────────────────────────────────────────────────────────────────────────┤"

    if ! is_enabled; then
        printf "│ %-74s │\n" "Bluetooth: disabled"
        echo "└────────────────────────────────────────────────────────────────────────────┘"
        return
    fi

    local connected_devices=()
    local paired_devices=()
    local discovered_devices=()

    # Get device information.
    local output
    output="$(bt_cmd devices)"

    if [[ -z "$output" ]]; then
        printf "│ %-74s │\n" "No Bluetooth devices found."
        echo "└────────────────────────────────────────────────────────────────────────────┘"
        return
    fi

    # Header
    printf "│ %-30s │ %-17s │ %-15s │\n" "Name" "Address" "Status"
    echo "├────────────────────────────────┼───────────────────┼─────────────────┤"

    while read -r _ mac name; do
        [[ -z "$mac" ]] && continue

        # bluetoothctl prints names with spaces after the MAC.
        # Reconstruct the complete name.
        name="${name:-Unknown}"

        local full_name
        full_name="$(echo "$output" |
            awk -v mac="$mac" '$2 == mac {
                $1=""; $2="";
                sub(/^  */, "");
                print;
                exit
            }')"

        [[ -z "$full_name" ]] && full_name="Unknown"

        local status="available"

        if bt_cmd info "$mac" | grep -q "Connected: yes"; then
            status="connected"
        elif bt_cmd info "$mac" | grep -q "Paired: yes"; then
            status="known"
        fi

        # Trim / truncate long names.
        full_name="${full_name#"${full_name%%[![:space:]]*}"}"
        full_name="${full_name%"${full_name##*[![:space:]]}"}"

        if (( ${#full_name} > 30 )); then
            full_name="${full_name:0:27}..."
        fi

        printf "│ %-30s │ %-17s │ %-15s │\n" \
            "$full_name" "$mac" "$status"

    done <<< "$output"

    echo "└────────────────────────────────┴───────────────────┴─────────────────┘"
    echo
}

# ---------- Bluetooth state ----------

enable_bluetooth() {
    if is_enabled; then
        echo "Bluetooth is already enabled."
        return
    fi

    echo "Enabling Bluetooth..."

    bt_cmd power on >/dev/null ||
        die "could not enable Bluetooth"

    echo "Bluetooth enabled."
}

disable_bluetooth() {
    if ! is_enabled; then
        echo "Bluetooth is already disabled."
        return
    fi

    echo "Disabling Bluetooth..."

    bt_cmd power off >/dev/null ||
        die "could not disable Bluetooth"

    echo "Bluetooth disabled."
}

# ---------- Scanning ----------

scan_bluetooth() {
    if ! is_enabled; then
        die "Bluetooth is disabled. Use -e/--enable first."
    fi

    echo "Scanning for Bluetooth devices..."
    echo "This will scan for approximately 10 seconds."
    echo

    bt_cmd scan on >/dev/null

    sleep 10

    bt_cmd scan off >/dev/null

    echo
    echo "Scan complete."

    show_table
}

# ---------- Connect ----------

connect_bluetooth() {
    local target="$1"

    [[ -n "$target" ]] ||
        die "missing device name or address"

    if ! is_enabled; then
        echo "Bluetooth is disabled. Enabling it..."
        enable_bluetooth
        sleep 1
    fi

    local mac=""

    # If an address was supplied, use it directly.
    if [[ "$target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        mac="$target"
    else
        # Look up device by name.
        mac="$(
            bt_cmd devices |
            while read -r _ address rest; do
                [[ "$rest" == "$target" ]] && {
                    echo "$address"
                    break
                }

                # Handle names containing spaces.
                local name
                name="$(echo "$rest")"

                if [[ "$name" == "$target" ]]; then
                    echo "$address"
                    break
                fi
            done
        )"

        # More reliable exact-name search.
        if [[ -z "$mac" ]]; then
            mac="$(
                bt_cmd devices |
                grep -F " $target" |
                awk '{print $2}' |
                head -n1
            )"
        fi
    fi

    if [[ -z "$mac" ]]; then
        echo "Device '$target' was not found."
        echo
        echo "Try:"
        echo "  bluetooth.sh -r"
        echo "and then connect using its address."
        exit 1
    fi

    echo "Connecting to $target ($mac)..."

    bt_cmd connect "$mac"

    if bt_cmd info "$mac" | grep -q "Connected: yes"; then
        echo
        echo "Connected."
    else
        echo
        echo "Connection failed."
        exit 1
    fi
}

# ---------- Pair ----------

pair_bluetooth() {
    local target="$1"

    [[ -n "$target" ]] ||
        die "missing device name or address"

    if ! is_enabled; then
        enable_bluetooth
        sleep 1
    fi

    local mac="$target"

    # Resolve name -> MAC.
    if ! [[ "$target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        mac="$(
            bt_cmd devices |
            grep -F " $target" |
            awk '{print $2}' |
            head -n1
        )"
    fi

    [[ -n "$mac" ]] ||
        die "device '$target' not found"

    echo "Pairing with $mac..."
    echo
    echo "If the device displays a pairing code, confirm it there."

    bt_cmd pair "$mac"

    if bt_cmd info "$mac" | grep -q "Paired: yes"; then
        echo
        echo "Paired successfully."
    else
        echo
        echo "Pairing may have failed."
        exit 1
    fi
}

# ---------- Trust ----------

trust_bluetooth() {
    local target="$1"

    [[ -n "$target" ]] ||
        die "missing device name or address"

    local mac="$target"

    if ! [[ "$target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        mac="$(
            bt_cmd devices |
            grep -F " $target" |
            awk '{print $2}' |
            head -n1
        )"
    fi

    [[ -n "$mac" ]] ||
        die "device '$target' not found"

    bt_cmd trust "$mac" >/dev/null ||
        die "could not trust device"

    echo "Device trusted."
}

# ---------- Disconnect ----------

disconnect_bluetooth() {
    local target="$1"

    if [[ -z "$target" ]]; then
        # Disconnect every connected device.
        local found=0

        while read -r _ mac _; do
            [[ -z "$mac" ]] && continue

            if bt_cmd info "$mac" | grep -q "Connected: yes"; then
                echo "Disconnecting $mac..."
                bt_cmd disconnect "$mac" >/dev/null
                found=1
            fi
        done < <(bt_cmd devices)

        (( found == 1 )) ||
            echo "No connected Bluetooth devices."

        return
    fi

    local mac="$target"

    if ! [[ "$target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        mac="$(
            bt_cmd devices |
            grep -F " $target" |
            awk '{print $2}' |
            head -n1
        )"
    fi

    [[ -n "$mac" ]] ||
        die "device '$target' not found"

    bt_cmd disconnect "$mac" >/dev/null ||
        die "could not disconnect device"

    echo "Disconnected."
}

# ---------- Forget ----------

forget_bluetooth() {
    local target="$1"

    [[ -n "$target" ]] ||
        die "missing device name or address"

    local mac="$target"

    if ! [[ "$target" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        mac="$(
            bt_cmd devices |
            grep -F " $target" |
            awk '{print $2}' |
            head -n1
        )"
    fi

    [[ -n "$mac" ]] ||
        die "device '$target' not found"

    echo "Removing $mac..."

    bt_cmd remove "$mac" >/dev/null ||
        die "could not remove device"

    echo "Device forgotten."
}

# ---------- Status ----------

show_status() {
    echo
    echo "Bluetooth status"
    echo "────────────────"

    bt_cmd show

    echo
    echo "Controller"
    echo "──────────"

    bt_cmd list
}

# ---------- Known devices ----------

show_known() {
    echo
    echo "Known Bluetooth devices"
    echo "───────────────────────"

    local found=0

    while read -r _ mac name; do
        [[ -z "$mac" ]] && continue

        local info
        info="$(bt_cmd info "$mac")"

        if echo "$info" | grep -q "Paired: yes"; then
            local full_name
            full_name="$(
                echo "$info" |
                sed -n 's/^[[:space:]]*Name:[[:space:]]*//p' |
                head -n1
            )"

            [[ -z "$full_name" ]] && full_name="Unknown"

            printf "  • %-30s %s\n" "$full_name" "$mac"
            found=1
        fi
    done < <(bt_cmd devices)

    (( found == 1 )) ||
        echo "  No known Bluetooth devices."
}

# ---------- Help ----------

show_help() {
    cat <<'EOF'

bluetooth.sh - Bluetooth controller

Usage:
  bluetooth.sh                         Show Bluetooth devices
  bluetooth.sh -c, --connect NAME      Connect to a device
  bluetooth.sh -p, --pair NAME         Pair with a device
  bluetooth.sh -t, --trust NAME        Trust a device
  bluetooth.sh -e, --enable            Enable Bluetooth
  bluetooth.sh -d, --disable           Disable Bluetooth
  bluetooth.sh -r, --rescan            Scan for devices
  bluetooth.sh -s, --status            Show Bluetooth status
  bluetooth.sh -k, --known             Show paired/known devices
  bluetooth.sh -x, --disconnect [NAME] Disconnect a device
  bluetooth.sh -f, --forget NAME       Forget/remove a device
  bluetooth.sh -h, --help              Show this help

Device names or Bluetooth MAC addresses can be used.

Examples:
  bluetooth.sh
  bluetooth.sh -r
  bluetooth.sh -c "WH-1000XM5"
  bluetooth.sh -c AA:BB:CC:DD:EE:FF
  bluetooth.sh -p "My Keyboard"
  bluetooth.sh -t "My Keyboard"
  bluetooth.sh -x
  bluetooth.sh -x "My Keyboard"
  bluetooth.sh -f "Old Headphones"

Device states:
  connected   Currently connected
  known       Paired with this computer
  available   Discovered but not paired

Pairing:
  Pairing may require confirmation or a PIN/passkey.
  bluetoothctl handles the authentication interaction.

EOF
}

# ---------- Argument parsing ----------

require_bluetoothctl

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
            [[ $# -ge 2 ]] ||
                die "option $1 requires a device name or address"

            connect_bluetooth "$2"
            shift
            ;;

        -p|--pair)
            [[ $# -ge 2 ]] ||
                die "option $1 requires a device name or address"

            pair_bluetooth "$2"
            shift
            ;;

        -t|--trust)
            [[ $# -ge 2 ]] ||
                die "option $1 requires a device name or address"

            trust_bluetooth "$2"
            shift
            ;;

        -e|--enable)
            enable_bluetooth
            ;;

        -d|--disable)
            disable_bluetooth
            ;;

        -r|--rescan)
            scan_bluetooth
            ;;

        -s|--status)
            show_status
            ;;

        -k|--known)
            show_known
            ;;

        -x|--disconnect)
            # Optional argument.
            if [[ $# -ge 2 && "$2" != -* ]]; then
                disconnect_bluetooth "$2"
                shift
            else
                disconnect_bluetooth
            fi
            ;;

        -f|--forget)
            [[ $# -ge 2 ]] ||
                die "option $1 requires a device name or address"

            forget_bluetooth "$2"
            shift
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
