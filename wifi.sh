#!/usr/bin/env bash

# ============================================================
# wifi.sh
# Wi-Fi manager for Armbian / Debian
#
# Backend:
#   iw                -> scanning
#   Netplan           -> configuration
#   systemd-networkd  -> networking
#   wpa_supplicant    -> Wi-Fi authentication
#
# Supports:
#   Open Wi-Fi
#   WPA/WPA2-Personal
#
# ============================================================

set -u

SCRIPT_NAME="$(basename "$0")"
CONFIG="/etc/netplan/99-wifi-manager.yaml"
IFACE=""

# ------------------------------------------------------------
# Colours
# ------------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    CYAN='\033[36m'
    RESET='\033[0m'
else
    BOLD=''
    DIM=''
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    RESET=''
fi

# ------------------------------------------------------------
# Basic helpers
# ------------------------------------------------------------

die() {
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}

info() {
    echo -e "${CYAN}→${RESET} $*"
}

success() {
    echo -e "${GREEN}✓${RESET} $*"
}

warning() {
    echo -e "${YELLOW}!${RESET} $*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "'$1' is required but is not installed."
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        exec sudo "$0" "$@"
    fi
}

# ------------------------------------------------------------
# Detect Wi-Fi interface
# ------------------------------------------------------------

detect_interface() {
    IFACE="$(iw dev 2>/dev/null |
        awk '$1 == "Interface" {print $2; exit}')"

    [[ -n "$IFACE" ]] ||
        die "No Wi-Fi interface found."

    echo "$IFACE"
}

# ------------------------------------------------------------
# YAML escaping
#
# Netplan YAML uses single-quoted strings.
#
# Example:
#   John's WiFi
#
# becomes:
#   'John''s WiFi'
# ------------------------------------------------------------

yaml_quote() {
    local value="$1"

    value="${value//\'/\'\'}"

    printf "'%s'" "$value"
}

# ------------------------------------------------------------
# Check Wi-Fi radio
# ------------------------------------------------------------

wifi_blocked() {
    rfkill list wifi 2>/dev/null |
        grep -qiE 'Soft blocked: yes|Hard blocked: yes'
}

enable_wifi() {
    require_root "$@"

    rfkill unblock wifi

    ip link set "$IFACE" up 2>/dev/null || true

    success "Wi-Fi enabled."
}

disable_wifi() {
    require_root "$@"

    rfkill block wifi

    success "Wi-Fi disabled."
}

# ------------------------------------------------------------
# Current connection
# ------------------------------------------------------------

get_connected_ssid() {
    iw dev "$IFACE" link 2>/dev/null |
        sed -n 's/^[[:space:]]*SSID: //p' |
        head -n 1
}

is_connected() {
    iw dev "$IFACE" link 2>/dev/null |
        grep -q '^Connected to '
}

# ------------------------------------------------------------
# Get known SSIDs from our Netplan file
# ------------------------------------------------------------

get_known_networks() {
    [[ -f "$CONFIG" ]] || return 0

    awk '
        /^      access-points:/ {
            in_ap=1
            next
        }

        in_ap && /^      [^ ]/ {
            in_ap=0
        }

        in_ap && /^        / {
            line=$0

            sub(/^        /, "", line)

            if (line ~ /^'\''/) {
                sub(/^'\''/, "", line)
                sub(/'\''$/, "", line)
                gsub(/'\'''\''/, "'\''", line)

                # Ignore password lines.
                if (line !~ /^password:/)
                    print line
            }
        }
    ' "$CONFIG"
}

is_known() {
    local target="$1"

    while IFS= read -r network; do
        [[ "$network" == "$target" ]] && return 0
    done < <(get_known_networks)

    return 1
}

# ------------------------------------------------------------
# Scan Wi-Fi networks
#
# Output:
#
# SSID<TAB>SECURITY<TAB>SIGNAL
#
# Hidden networks are ignored.
# Duplicate SSIDs are collapsed.
# ------------------------------------------------------------

scan_networks() {
    local output

    ip link set "$IFACE" up 2>/dev/null || true

    output="$(iw dev "$IFACE" scan 2>/dev/null)" ||
        return 0

    awk '
        function emit() {
            if (ssid != "") {
                printf "%s\t%s\t%s\n",
                    ssid,
                    security,
                    signal
            }
        }

        /^BSS / {
            emit()

            ssid=""
            signal=""
            security="OPEN"
            next
        }

        /^[[:space:]]*SSID: / {
            value=$0
            sub(/^[[:space:]]*SSID: /, "", value)

            if (value != "")
                ssid=value

            next
        }

        /^[[:space:]]*signal:/ {
            value=$0
            sub(/^[[:space:]]*signal: /, "", value)
            sub(/ dBm.*/, "", value)

            signal=value

            next
        }

        /^[[:space:]]*RSN:/ {
            security="WPA2"
            next
        }

        /^[[:space:]]*WPA:/ {
            if (security == "OPEN")
                security="WPA"

            next
        }

        END {
            emit()
        }
    ' <<< "$output" |
    awk -F '\t' '
        {
            ssid=$1

            # Keep first occurrence.
            if (!(ssid in seen)) {
                seen[ssid]=1
                print
            }
        }
    ' |
    sort -t $'\t' -k3,3nr
}

# ------------------------------------------------------------
# Draw table
# ------------------------------------------------------------

show_table() {
    local scan
    local connected
    local ssid
    local security
    local signal
    local state
    local display
    local count=0

    connected="$(get_connected_ssid)"

    scan="$(scan_networks)"

    echo
    echo "┌────────────────────────────────┬────────────┬──────────┐"
    printf "│ %-30s │ %-10s │ %-8s │\n" \
        "NAME" "STATE" "SECURITY"
    echo "├────────────────────────────────┼────────────┼──────────┤"

    if [[ -n "$scan" ]]; then
        while IFS=$'\t' read -r ssid security signal; do
            [[ -n "$ssid" ]] || continue

            ((count++))

            if [[ "$ssid" == "$connected" ]]; then
                state="CONNECTED"
            elif is_known "$ssid"; then
                state="KNOWN"
            else
                state="AVAILABLE"
            fi

            display="$ssid"

            if (( ${#display} > 30 )); then
                display="${display:0:27}..."
            fi

            printf "│ %-30s │ %-10s │ %-8s │\n" \
                "$display" "$state" "$security"

        done <<< "$scan"
    fi

    if (( count == 0 )); then
        printf "│ %-30s │ %-10s │ %-8s │\n" \
            "No networks found" "-" "-"
    fi

    echo "└────────────────────────────────┴────────────┴──────────┘"
    echo
}

# ------------------------------------------------------------
# Create Netplan configuration
#
# We replace ONLY our own 99-wifi-manager.yaml file.
# Other Netplan files are untouched.
# ------------------------------------------------------------

write_config() {
    local ssid="$1"
    local password="${2:-}"

    local quoted_ssid

    quoted_ssid="$(yaml_quote "$ssid")"

    mkdir -p /etc/netplan

    cat > "$CONFIG" <<EOF
network:
  version: 2
  renderer: networkd

  wifis:
    $IFACE:
      dhcp4: true
      dhcp6: true
      access-points:
        $quoted_ssid:
EOF

    if [[ -n "$password" ]]; then
        local quoted_password
        quoted_password="$(yaml_quote "$password")"

        printf "          password: %s\n" "$quoted_password" >> "$CONFIG"
    else
        printf "          {}\n" >> "$CONFIG"
    fi

    chmod 600 "$CONFIG"
}

# ------------------------------------------------------------
# Validate Netplan
# ------------------------------------------------------------

validate_config() {
    netplan generate 2>&1
}

# ------------------------------------------------------------
# Connect
# ------------------------------------------------------------

connect_wifi() {
    require_root "$@"

    local ssid="$1"
    local password=""

    [[ -n "$ssid" ]] ||
        die "SSID cannot be empty."

    echo
    info "Connecting to: $ssid"
    echo

    # Make sure Wi-Fi isn't blocked.
    rfkill unblock wifi
    ip link set "$IFACE" up 2>/dev/null || true

    # --------------------------------------------------------
    # Determine whether this network is open.
    # --------------------------------------------------------

    local security=""

    while IFS=$'\t' read -r found_ssid found_security found_signal; do
        if [[ "$found_ssid" == "$ssid" ]]; then
            security="$found_security"
            break
        fi
    done < <(scan_networks)

    # --------------------------------------------------------
    # If we couldn't determine security, ask.
    # --------------------------------------------------------

    if [[ "$security" == "OPEN" ]]; then
        info "Open network detected."
    else
        echo -n "Password: "
        read -r -s password
        echo

        if [[ -z "$password" ]]; then
            die "Password cannot be empty for a secured network."
        fi
    fi

    # --------------------------------------------------------
    # Save configuration.
    # --------------------------------------------------------

    info "Writing Netplan configuration..."

    write_config "$ssid" "$password"

    # --------------------------------------------------------
    # Validate before applying.
    # --------------------------------------------------------

    info "Validating Netplan configuration..."

    if ! validate_config; then
        rm -f "$CONFIG"

        die "Netplan rejected the configuration."
    fi

    # --------------------------------------------------------
    # Apply.
    # --------------------------------------------------------

    info "Applying configuration..."

    if ! netplan apply; then
        die "Netplan failed to apply the configuration."
    fi

    echo
    info "Waiting for connection..."

    local i

    for i in {1..20}; do
        sleep 1

        if is_connected; then
            local current

            current="$(get_connected_ssid)"

            if [[ "$current" == "$ssid" ]]; then
                echo
                success "Connected to $ssid."

                local ip

                ip="$(ip -4 -o addr show "$IFACE" |
                    awk '{print $4}' |
                    head -n 1)"

                [[ -n "$ip" ]] &&
                    info "IPv4 address: $ip"

                return 0
            fi
        fi

        printf "."
    done

    echo
    echo
    warning "Connection was not established."

    info "Current interface status:"
    networkctl status "$IFACE" --no-pager 2>/dev/null || true

    return 1
}

# ------------------------------------------------------------
# Disconnect
# ------------------------------------------------------------

disconnect_wifi() {
    require_root "$@"

    if ! is_connected; then
        warning "Wi-Fi is not currently connected."
        return 0
    fi

    info "Disconnecting..."

    ip link set "$IFACE" down 2>/dev/null || true

    success "Disconnected."
}

# ------------------------------------------------------------
# Forget current known network
# ------------------------------------------------------------

forget_wifi() {
    require_root "$@"

    local target="$1"

    [[ -n "$target" ]] ||
        die "Specify a network to forget."

    [[ -f "$CONFIG" ]] ||
        die "No saved Wi-Fi networks."

    local temp
    temp="$(mktemp)"

    awk -v target="$target" '
        BEGIN {
            skip=0
        }

        /^        / {
            line=$0
            sub(/^        /, "", line)

            if (line ~ /^'\''/) {
                name=line
                sub(/^'\''/, "", name)
                sub(/'\''$/, "", name)
                gsub(/'\'''\''/, "'\''", name)

                if (name == target) {
                    skip=1
                    next
                }

                skip=0
            }
        }

        skip && /^          / {
            next
        }

        {
            print
        }
    ' "$CONFIG" > "$temp"

    mv "$temp" "$CONFIG"

    chmod 600 "$CONFIG"

    netplan generate 2>/dev/null || true

    success "Forgot: $target"
}

# ------------------------------------------------------------
# Show status
# ------------------------------------------------------------

show_status() {
    local connected

    connected="$(get_connected_ssid)"

    echo
    echo "Wi-Fi interface: $IFACE"

    if wifi_blocked; then
        echo "Radio:           disabled"
    else
        echo "Radio:           enabled"
    fi

    if [[ -n "$connected" ]]; then
        echo "Connection:      connected"
        echo "SSID:            $connected"
    else
        echo "Connection:      disconnected"
    fi

    local ip

    ip="$(ip -4 -o addr show "$IFACE" |
        awk '{print $4}' |
        head -n 1)"

    if [[ -n "$ip" ]]; then
        echo "IPv4:            $ip"
    else
        echo "IPv4:            none"
    fi

    echo
}

# ------------------------------------------------------------
# Rescan
# ------------------------------------------------------------

rescan() {
    if wifi_blocked; then
        warning "Wi-Fi is disabled."
        return 1
    fi

    info "Scanning..."

    show_table
}

# ------------------------------------------------------------
# Known networks
# ------------------------------------------------------------

show_known() {
    local found=0

    echo
    echo "┌──────────────────────────────────────────┐"
    printf "│ %-40s │\n" "KNOWN NETWORKS"
    echo "├──────────────────────────────────────────┤"

    while IFS= read -r ssid; do
        [[ -n "$ssid" ]] || continue

        found=1

        local display="$ssid"

        if (( ${#display} > 40 )); then
            display="${display:0:37}..."
        fi

        printf "│ %-40s │\n" "$display"
    done < <(get_known_networks)

    if (( found == 0 )); then
        printf "│ %-40s │\n" "No saved networks"
    fi

    echo "└──────────────────────────────────────────┘"
    echo
}

# ------------------------------------------------------------
# Help
# ------------------------------------------------------------

show_help() {
    cat <<EOF

$SCRIPT_NAME - Wi-Fi manager

Usage:
  $SCRIPT_NAME
  $SCRIPT_NAME [command] [arguments]

Commands:

  -c, --connect NAME
      Connect to a Wi-Fi network.

  -d, --disable
      Disable Wi-Fi.

  -e, --enable
      Enable Wi-Fi.

  -r, --rescan
      Scan for nearby Wi-Fi networks.

  -s, --status
      Show Wi-Fi status.

  -k, --known
      Show saved/known networks.

  -x, --disconnect
      Disconnect from the current Wi-Fi.

  -f, --forget NAME
      Forget a saved network.

  -h, --help
      Show this help.

Examples:

  $SCRIPT_NAME
  sudo $SCRIPT_NAME --connect "My WiFi"
  sudo $SCRIPT_NAME -e
  sudo $SCRIPT_NAME -d
  $SCRIPT_NAME -r
  $SCRIPT_NAME -s
  $SCRIPT_NAME -k
  sudo $SCRIPT_NAME -x
  sudo $SCRIPT_NAME -f "My WiFi"

Notes:

  Wi-Fi configuration is stored in:

    $CONFIG

  The script uses:

    iw
    netplan
    systemd-networkd
    wpa_supplicant

EOF
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {
    require_root "$@"

    require_command iw
    require_command rfkill
    require_command netplan
    require_command ip

    IFACE="$(detect_interface)"

    # No arguments:
    # print help hint + table
    if [[ $# -eq 0 ]]; then
        echo "use -h for help"

        if wifi_blocked; then
            warning "Wi-Fi is disabled."
        else
            show_table
        fi

        exit 0
    fi

    case "$1" in

        -c|--connect)
            [[ $# -ge 2 ]] ||
                die "Usage: $SCRIPT_NAME --connect \"SSID\""

            connect_wifi "$2"
            ;;

        -e|--enable)
            enable_wifi
            ;;

        -d|--disable)
            disable_wifi
            ;;

        -r|--rescan)
            rescan
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

        -f|--forget)
            [[ $# -ge 2 ]] ||
                die "Usage: $SCRIPT_NAME --forget \"SSID\""

            forget_wifi "$2"
            ;;

        -h|--help)
            show_help
            ;;

        *)
            die "Unknown option: $1 (use -h for help)"
            ;;

    esac
}

main "$@"
