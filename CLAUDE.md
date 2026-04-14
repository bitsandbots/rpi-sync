# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PiSync is a single-file bash CLI (`pisync`) that synchronizes project directories across Raspberry Pi nodes over LAN using rsync/SSH with zero-config Avahi/mDNS discovery. MIT-licensed, cloud-independent, offline-first.

No build step. No test runner. No package manager. Development = edit `pisync`, test manually.

## Commands

```bash
# Install on a node
sudo ./install.sh                   # to /usr/local/bin
./install.sh --prefix ~/.local      # to ~/.local/bin (no sudo)
./install.sh --check                # verify deps only
sudo ./install.sh --uninstall       # remove binary

# Verify installation and connectivity
bash healthcheck.sh

# Run directly without installing
bash pisync <command>

# Common dev cycle: edit pisync, then test a subcommand
bash pisync --help
bash pisync init
bash pisync dry-run

# Release a new version
./release.sh 1.1.0 --dry-run       # preview
./release.sh 1.1.0                  # bump, build dist/, tag
```

## Architecture

**Everything lives in `pisync`** — one bash script, ~800 lines, `set -euo pipefail`.

| Layer | Details |
|---|---|
| Entry | `main()` dispatches via `case` on `$1` |
| Config | Sourced bash file at `~/.pisync/pisync.conf` — pipe-delimited `PROJECT_NN` and `NODE_NN` vars |
| State | `~/.pisync/state/{project}_{host}.last` — ISO timestamp + direction + duration + result |
| Locking | `~/.pisync/pisync.lock` — PID file, stale-lock detection on acquire |
| Sync | `sync_project_to_node()` → `rsync -azP --checksum --delete` over SSH |
| Watch | `inotifywait -m -r` with 2s debounce via background subshell + `kill $debounce_pid` |
| Discovery | Avahi/mDNS (`_pisync._tcp`) → subnet TCP scan → configured nodes check |
| Daemon | `cmd_daemon()` loop with `sleep $DAEMON_INTERVAL`; systemd unit written by `cmd_install_service()` |

**Config format** (parsed with `grep '^PROJECT_'` / `grep '^NODE_'`, not `source`):
```
PROJECT_01="name|local_path|remote_path|exclude_file"
NODE_01="name|host|user|port"
```

**Rsync flags always included:** `-azP --delete --checksum --timeout=30 --stats --human-readable --itemize-changes`

Default excludes hardcoded in `build_rsync_args()`: `.git/objects`, `__pycache__`, `*.pyc`, `node_modules`, `.DS_Store`, `*.swp/swo`, `.pisync-local`.

## File map

| File | Purpose |
|---|---|
| `pisync` | The entire tool — all subcommands, sync engine, discovery |
| `install.sh` | Installs binary + deps; supports `--prefix`, `--check`, `--uninstall` |
| `release.sh` | Bumps version, builds `dist/pisync-vX.Y.Z.tar.gz`, creates git tag |
| `healthcheck.sh` | Pre-flight checks: deps, config, node reachability, SSH auth, systemd service |
| `templates/excludes/` | Rsync exclude templates for `claude-harness`, `hydromazing`, `nexus` |
| `dist/` | Generated release tarballs — gitignored, produced by `release.sh` |

## Key conventions

- All user-facing messages go through `info()` / `warn()` / `error()` / `step()` — each logs to `$PISYNC_LOG` AND prints with color.
- Lock must be acquired before any write operation; always `trap release_lock EXIT` in long-running commands.
- SSH calls use `-o BatchMode=yes -o ConnectTimeout=N` — never prompt for passwords.
- The `dry-run` subcommand sets `DRY_RUN=true` then calls `sync_project` — the flag is checked inside `sync_project_to_node()`.
- All loops that consume `get_projects` / `get_nodes` must use process substitution `< <(get_projects)` not pipes — pipes run in a subshell and variable assignments are lost.

## Dependencies

Required: `rsync`, `openssh-client`, `openssh-server`
Optional: `avahi-utils` (mDNS discovery), `inotify-tools` (watch mode)
