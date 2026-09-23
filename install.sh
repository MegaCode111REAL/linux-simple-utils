#!/usr/bin/env bash
set -euo pipefail
REPO="MegaCode111REAL/linux-simple-utils"
INSTALL_DIR="${HOME}/.local/sbin"
UTILS=(wifi bluetooth network audio display power system users storage software security)
usage() { cat <<'EOF'
linux-simple-utils installer
Usage:
  install.sh
  install.sh TAG
Installs the latest stable release unless TAG is supplied.
EOF
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
[[ $# -le 1 ]] || { usage >&2; exit 1; }
TAG="${1:-latest}"
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required." >&2; exit 1; }
mkdir -p "$INSTALL_DIR"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
download_asset() {
    local name="$1" url
    if [[ "$TAG" == "latest" ]]; then
        url="https://github.com/${REPO}/releases/latest/download/${name}"
    else
        url="https://github.com/${REPO}/releases/download/${TAG}/${name}"
    fi
    echo "Downloading $name..."
    curl --fail --location --silent --show-error "$url" -o "$tmpdir/$name"
}
for name in "${UTILS[@]}"; do
    download_asset "$name"
    [[ -s "$tmpdir/$name" ]] || { echo "Error: downloaded $name is empty." >&2; exit 1; }
    install -m 755 "$tmpdir/$name" "$INSTALL_DIR/$name"
done
PATH_LINE='export PATH="$HOME/.local/sbin:$PATH"'
for file in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    touch "$file"
    if ! grep -Fqx "$PATH_LINE" "$file"; then
        printf '\n# linux-simple-utils\n%s\n' "$PATH_LINE" >> "$file"
    fi
done
echo
echo "Installed ${#UTILS[@]} utilities to $INSTALL_DIR."
echo
echo "Open a new terminal, or run:"
echo '  export PATH="$HOME/.local/sbin:$PATH"'
echo
echo "Available commands:"
printf '  %s\n' "${UTILS[@]}"
