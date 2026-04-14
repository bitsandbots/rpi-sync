# PiSync — Tech Stack

## Runtime dependencies

All required packages are installed automatically by `install.sh` on Debian/Ubuntu/Raspberry Pi OS.

| Tool | Package | Purpose | Required |
|------|---------|---------|----------|
| `rsync` | `rsync` | Delta file transfer engine | Yes |
| `ssh` / `sshd` | `openssh-client` + `openssh-server` | Encrypted transport, authentication | Yes |
| `avahi-browse` | `avahi-utils` | mDNS/Zeroconf LAN node discovery | Optional — falls back to subnet scan |
| `inotifywait` | `inotify-tools` | Filesystem event watch for auto-sync | Optional — required for `pisync watch` |

## System requirements

| Item | Minimum | Notes |
|------|---------|-------|
| OS | Debian 11 / Raspberry Pi OS Bullseye | Any Debian/Ubuntu derivative works |
| Bash | 4.0+ | Uses `[[ ]]`, `<()` process substitution, arrays |
| Python | Not required | Pure bash |
| Disk | Negligible for PiSync itself | Varies by projects being synced |
| Network | LAN connectivity between nodes | SSH port (default 22) must be reachable |

## Build / packaging

None. PiSync is a single bash script. `install.sh` copies it to `/usr/local/bin/pisync` and sets the executable bit. No compilation, no package manager, no virtualenv.

## Systemd integration

`pisync install-service` writes two files:

| File | Purpose |
|------|---------|
| `/etc/systemd/system/pisync.service` | Service unit — runs `pisync daemon` as the installing user |
| `/etc/avahi/services/pisync.service` | Avahi XML descriptor — advertises `_pisync._tcp` on port 22 |

The service unit requires `network-online.target` and optionally `avahi-daemon.service`.

## Platform notes

- **Raspberry Pi 5 / 4 / Zero 2W**: Fully supported. Tested on Pi OS Bookworm and Bullseye.
- **macOS**: `inotifywait` is Linux-only; watch mode unavailable. Avahi not available by default. Sync, push, pull, and daemon mode work via rsync/SSH.
- **Other Linux**: Any distro with bash 4+, rsync, and openssh works. Replace `apt` commands in `install.sh` for non-Debian systems.
