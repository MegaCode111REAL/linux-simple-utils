# linux-simple-utils

Small Linux command-line utilities for settings you would normally find in a desktop Settings app.

## Commands

```text
wifi
bluetooth
network
audio
display
power
system
users
storage
software
security
```

## Install

```bash
curl -fsSL https://github.com/MegaCode111REAL/linux-simple-utils/releases/latest/download/install.sh | bash
```

The installer installs extensionless commands to `~/.local/sbin` and adds that directory to your PATH.

Commands automatically request sudo when they need root privileges.

## Utilities

| Command | Purpose |
| --- | --- |
| `wifi` | Wi-Fi settings and connections |
| `bluetooth` | Bluetooth devices and connections |
| `network` | General network settings |
| `audio` | Audio devices, volume and mute |
| `display` | Display and monitor settings |
| `power` | Power, battery and power-profile controls |
| `system` | System information and hostname |
| `users` | Local user/account management |
| `storage` | Disks, filesystems and mounts |
| `software` | Packages and system updates |
| `security` | Firewall and SSH settings |

Every utility supports `--help`.

## Releases

Use the **Create Release** workflow in GitHub Actions. It lets you enter a custom version, release name, release notes, and whether the release is a draft or pre-release.

Each release contains extensionless executable assets for every utility and an `install.sh` asset.

## Compatibility

The utilities use common Linux tools and native backends where practical. Some features depend on installed software such as NetworkManager, PipeWire/WirePlumber, PulseAudio, X11, UFW or firewalld.

They are primarily intended for Debian/Ubuntu/Armbian-style systems, with several utilities supporting other distributions too.
