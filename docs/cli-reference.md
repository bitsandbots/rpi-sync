# rpi-sync — CLI Reference

All commands follow the form: `rpi-sync <command> [arguments]`

---

## Setup commands

### `rpi-sync init`

Initializes rpi-sync on this node. Creates `~/.rpi-sync/rpi-sync.conf` and the default exclude file for the `.claude` harness. Prompts before overwriting an existing config.

```bash
rpi-sync init
```

---

### `rpi-sync add-node <name> <host> [user] [port]`

Registers a peer node and appends a `NODE_NN` entry to `rpi-sync.conf`. Prompts to deploy SSH keys immediately.

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `name` | Yes | — | Identifier used in sync commands |
| `host` | Yes | — | IP address or hostname |
| `user` | No | `$USER` | SSH user on the remote node |
| `port` | No | `22` | SSH port |

All arguments are validated against shell metacharacters before being written to the config.

```bash
rpi-sync add-node pi-workshop 192.168.1.101
rpi-sync add-node pi-garden   192.168.1.102 cory 2222
```

---

### `rpi-sync add-project <name> <path> [remote_path] [exclude_file]`

Registers a project to sync and appends a `PROJECT_NN` entry to `rpi-sync.conf`.

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `name` | Yes | — | Identifier used in sync commands |
| `path` | Yes | — | Absolute local path |
| `remote_path` | No | same as `path` | Absolute path on remote nodes |
| `exclude_file` | No | `""` | Path to an rsync exclude pattern file |

```bash
rpi-sync add-project hydromazing /home/pi/projects/hydromazing
rpi-sync add-project nexus /home/pi/projects/nexus /home/pi/projects/nexus ~/.rpi-sync/excludes/nexus.exclude
```

---

### `rpi-sync keys <host> [user]`

Generates an Ed25519 SSH key pair (if none exists) and deploys it to the target host via `ssh-copy-id`. Logs the host key fingerprint before connecting.

```bash
rpi-sync keys 192.168.1.101
rpi-sync keys 192.168.1.101 cory
```

---

### `rpi-sync install-service`

Installs and starts the rpi-sync systemd daemon. Writes:
- `/etc/systemd/system/rpi-sync.service`
- `/etc/avahi/services/rpi-sync.service` (if Avahi is installed)

Requires `sudo` privileges (the script prompts via `sudo tee`).

```bash
rpi-sync install-service
```

---

## Sync commands

### `rpi-sync sync [project] [node]`

Syncs in the direction set by `DEFAULT_DIRECTION` in config (default: `push`). Both arguments default to `all`.

```bash
rpi-sync sync                            # all projects → all nodes
rpi-sync sync claude-harness             # one project → all nodes
rpi-sync sync claude-harness pi-workshop # one project → one node
```

---

### `rpi-sync push [project] [node]`

Force push regardless of `DEFAULT_DIRECTION`. Local is authoritative.

```bash
rpi-sync push
rpi-sync push hydromazing
rpi-sync push hydromazing pi-garden
```

---

### `rpi-sync pull [project] [node]`

Force pull regardless of `DEFAULT_DIRECTION`. Remote is authoritative.

```bash
rpi-sync pull
rpi-sync pull claude-harness pi-workshop
```

---

### `rpi-sync deploy [project]`

Pushes to all configured nodes with a dry-run preview and confirmation prompt. Also syncs the node list to remotes so they can run rpi-sync independently. Reports successes and failures at the end.

```bash
rpi-sync deploy              # deploy all projects
rpi-sync deploy claude-harness  # deploy specific project
```

**Flow:**
1. Shows dry-run preview of what would be synced
2. Prompts for confirmation (y/N)
3. Pushes projects to all configured nodes
4. Syncs node list to each remote (preserving remote's identity)
5. Reports successes and failures

**What gets synced to remotes:**
- Project files (via rsync)
- `NODE_*` entries from config (so remotes know about all peers)

**What stays local on remotes:**
- `NODE_NAME` - remote's own hostname
- `SYNC_USER` - remote's user
- Other local settings

---

### `rpi-sync dry-run [project] [node]`

Shows what rsync would transfer without making any changes. Sets `DRY_RUN=true` and calls `sync_project` — no files are modified.

```bash
rpi-sync dry-run
rpi-sync dry-run nexus pi-workshop
```

---

### `rpi-sync watch <project>`

Watches the project's local directory with `inotifywait` and triggers a sync 2 seconds after the last file change (debounced). Runs in the foreground; press `Ctrl+C` to stop.

Requires `inotify-tools`.

```bash
rpi-sync watch claude-harness
```

---

## Status commands

### `rpi-sync status`

Shows connectivity status for all configured nodes (SSH reachable + uptime) and the last sync result for each project+node pair.

```bash
rpi-sync status
```

Example output:
```
  Node Status
  ─────────────────────────────────────────
  ● pi-workshop (192.168.1.101) — up 2 hours, 14 minutes
  ● pi-garden   (192.168.1.102) — offline

  Last Sync Status
  ─────────────────────────────────────────
  ✓ claude-harness_pi-workshop: push 4s (2026-04-14T10:30:00+00:00)
```

---

### `rpi-sync discover`

Scans the LAN for rpi-sync nodes using three methods in order:
1. Avahi/mDNS (`_pisync._tcp`)
2. TCP port-22 scan of the local `/24` subnet
3. Connectivity check of all configured `NODE_*` entries

```bash
rpi-sync discover
```

---

### `rpi-sync conflicts <project> <node>`

Compares file hashes between the local project directory and the remote node using `md5sum`. Reports the number of differing files and shows the first 20 lines of the diff.

```bash
rpi-sync conflicts claude-harness pi-workshop
```

---

### `rpi-sync log [lines]`

Tails the rpi-sync log file. Defaults to 50 lines.

```bash
rpi-sync log
rpi-sync log 200
```

Log location: `~/.rpi-sync/rpi-sync.log`

---

## Internal commands

### `rpi-sync daemon`

Runs the sync loop used by the systemd service. Syncs all projects on the configured `DAEMON_INTERVAL`, with lock acquisition between cycles. Not typically invoked directly — use `rpi-sync install-service` instead.

---

## Global flags

| Flag | Description |
|------|-------------|
| `--version`, `-v` | Print version string |
| `--help`, `-h` | Show usage |

---

## rsync flags applied to every sync

These flags are always passed by `build_rsync_args()` and cannot be overridden from the CLI:

| Flag | Effect |
|------|--------|
| `-a` | Archive mode — preserves permissions, timestamps, symlinks |
| `-z` | Compression during transfer |
| `-P` | Partial file resume + progress output |
| `--delete` | Remove files on destination that no longer exist in source |
| `--checksum` | Compare by file content hash, not just size/timestamp |
| `--timeout=30` | Abort if no data received for 30 seconds |
| `--stats` | Print transfer statistics |
| `--human-readable` | Human-readable sizes in stats |
| `--itemize-changes` | Show per-file change type |

### Built-in default excludes (always applied)

```
.git/objects
__pycache__
*.pyc
node_modules
.DS_Store
*.swp
*.swo
.rpi-sync-local
```
