# rpi-sync — Architecture

## High-level topology

```
┌─────────────────────┐     rsync/SSH      ┌─────────────────────┐
│  pi-primary         │◄──────────────────►│  pi-workshop        │
│  ├─ .claude/        │                    │  ├─ .claude/        │
│  ├─ hydromazing/    │     Avahi/mDNS     │  ├─ hydromazing/    │
│  └─ ~/.rpi-sync/    │◄──── discovery ───►│  └─ ~/.rpi-sync/    │
└─────────────────────┘                    └─────────────────────┘
         ▲                                          ▲
         │            rsync/SSH                     │
         └──────────────┬──────────────────────────┘
                        │
               ┌────────┴────────┐
               │  pi-garden      │
               │  ├─ .claude/    │
               │  └─ ~/.rpi-sync/│
               └─────────────────┘
```

- **No central server** — any node can push or pull from any other.
- **SSH transport** — encrypted, authenticated, uses your existing keys.
- **Avahi/mDNS** — nodes advertise `_rpi-sync._tcp` for automatic LAN discovery.

## Runtime directory layout

All rpi-sync state lives in `~/.rpi-sync/` on each node:

```
~/.rpi-sync/
├── rpi-sync.conf          # Main configuration (sourced as bash)
├── rpi-sync.log           # Append-only operation log
├── rpi-sync.lock          # PID lock file (present only while running)
├── state/
│   ├── claude-harness_pi-workshop.last   # Last sync result per project+node
│   └── hydromazing_pi-garden.last
└── excludes/
    ├── claude-harness.exclude   # rsync exclude patterns for this project
    ├── hydromazing.exclude
    └── nexus.exclude
```

### State file format

Each `state/{project}_{host}.last` file contains one line:

```
2026-04-14T10:30:00+00:00|push|4s|success
```

Fields: ISO timestamp | direction | duration | result (`success` or `failed`)

## Code structure

rpi-sync is a **single bash script** (`rpi-sync`, ~820 lines). All logic lives in one file.

### Function groups

| Group | Functions | Responsibility |
|-------|-----------|----------------|
| Bootstrap | `init_dirs`, `load_config`, `get_projects`, `get_nodes` | Setup and config parsing |
| Locking | `acquire_lock`, `release_lock` | Prevent concurrent daemon runs |
| Discovery | `discover_nodes` | Avahi + subnet scan + configured nodes |
| SSH | `setup_keys` | Ed25519 key generation and deployment |
| Sync engine | `build_rsync_args`, `sync_project_to_node`, `sync_project` | Core transfer logic |
| Conflict detection | `check_conflicts` | Hash-based manifest comparison via SSH |
| Watch mode | `watch_and_sync` | inotify event loop with 2s debounce |
| Commands | `cmd_init`, `cmd_add_node`, `cmd_add_project`, `cmd_install_service`, `cmd_daemon`, `cmd_log` | Subcommand implementations |
| UI | `banner`, `log`, `info`, `warn`, `error`, `step`, `usage`, `show_status` | Output and status display |
| Entry | `main` | Subcommand dispatch via `case` |

## Data flow: push sync

```
rpi-sync sync claude-harness pi-workshop
        │
        ▼
main() → sync_project("claude-harness", "push", "pi-workshop")
        │
        ├─ load_config()          reads ~/.rpi-sync/rpi-sync.conf
        │
        ├─ get_projects()         greps PROJECT_* lines → pipe-delimited fields
        │
        ├─ get_nodes()            greps NODE_* lines → pipe-delimited fields
        │
        └─ sync_project_to_node()
                │
                ├─ build_rsync_args()   assembles flag array + exclude files
                │
                ├─ rsync -azP --checksum --delete \
                │         -e "ssh -p 22 -o BatchMode=yes" \
                │         /local/path/ user@host:/remote/path/
                │
                └─ write state file: ~/.rpi-sync/state/claude-harness_pi-workshop.last
```

## Data flow: watch mode

```
rpi-sync watch claude-harness
        │
        ▼
main() → watch_and_sync("claude-harness", "/home/pi/.claude")
        │
        └─ inotifywait -m -r -e modify,create,delete,move /home/pi/.claude
                │
                └─ on event: kill previous debounce timer (if any)
                             start new background subshell:
                               sleep 2
                               sync_project("claude-harness")
```

The 2-second debounce prevents a burst of file saves (e.g. editor write) from triggering multiple syncs.

## Node discovery: fallback chain

```
discover_nodes()
    │
    ├─ 1. avahi-browse -t -r _rpi-sync._tcp
    │       Finds nodes advertising the _rpi-sync._tcp mDNS service.
    │       Fast, zero-config, preferred.
    │
    ├─ 2. TCP scan of /24 subnet on port 22
    │       SSH-connects to each reachable host, checks for
    │       ~/.rpi-sync/rpi-sync.conf presence. Slow (~30s for /24).
    │
    └─ 3. Connectivity check of configured NODE_* entries
            Shows online/offline status for already-known nodes.
```

## Locking

The lock file at `~/.rpi-sync/rpi-sync.lock` contains the current PID. On `acquire_lock`:

1. If lock file absent → write PID, proceed.
2. If lock file present → check if PID is still alive (`kill -0`).
   - Alive → error and return 1.
   - Dead → remove stale lock, write new PID, proceed.

The daemon releases the lock between interval sleeps so manual `rpi-sync sync` commands can run concurrently with the daemon's sleep period.

## Security model

- All transfers use SSH with `BatchMode=yes` — no interactive prompts.
- Node/project names and paths are validated against shell metacharacters (`$`, `` ` ``, `()`, `|`, `&`, `<>`) before being written to `rpi-sync.conf`, which is `source`d by bash.
- Remote paths in SSH commands are escaped with `printf '%q'` before interpolation.
- SSH key deployment uses `StrictHostKeyChecking=no` (TOFU) and logs the host key fingerprint to `rpi-sync.log` for auditability.
