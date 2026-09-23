#!/usr/bin/env bash

set -euo pipefail

REPO="MegaCode111REAL/linux-simple-utils"
INSTALL_DIR="${HOME}/.local/sbin"

usage() {
    cat <<'EOF'
linux-simple-utils installer

Usage:
  install.sh
  install.sh TAG

If TAG is omitted, the latest stable release is installed.
Example:
  install.sh v1.0.0
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -gt 1 ]]; then
    usage >&2
    exit 1
fi

TAG="${1:-latest}"

command -v curl >/dev/null 2>&1 ||
    { echo "Error: curl is required." >&2; exit 1; }

mkdir -p "$INSTALL_DIR"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

download_asset() {
    local name="$1"
    local url

    if [[ "$TAG" == "latest" ]]; then
        url="https://github.com/${REPO}/releases/latest/download/${name}"
    else
        url="https://github.com/${REPO}/releases/download/${TAG}/${name}"
    fi

    echo "Downloading $name..."
    curl --fail --location --silent --show-error "$url" -o "$tmpdir/$name"
}

download_asset wifi
download_asset bluetooth

for name in wifi bluetooth; do
    [[ -s "$tmpdir/$name" ]] ||
        { echo "Error: downloaded $name is empty." >&2; exit 1; }

    chmod 755 "$tmpdir/$name"
    install -m 755 "$tmpdir/$name" "$INSTALL_DIR/$name"
done

PATH_LINE='export PATH="$HOME/.local/sbin:$PATH"'

add_path_line() {
    local file="$1"

    touch "$file"

    if ! grep -Fqx "$PATH_LINE" "$file"; then
        printf '\n# linux-simple-utils\n%s\n' "$PATH_LINE" >> "$file"
    fi
}

add_path_line "$HOME/.profile"
add_path_line "$HOME/.bashrc"
add_path_line "$HOME/.zshrc"

echo
echo "Installed:"
echo "  $INSTALL_DIR/wifi"
echo "  $INSTALL_DIR/bluetooth"
echo
echo "Open a new terminal, or run:"
echo '  export PATH="$HOME/.local/sbin:$PATH"'
echo
echo "Then use:"
echo "  wifi"
echo "  bluetooth"
