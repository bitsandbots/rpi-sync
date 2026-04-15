# PiSync — CLI Reference

All commands follow the form: `pisync <command> [arguments]`

---

## Setup commands

### `pisync init`

Initializes PiSync on this node. Creates `~/.pisync/pisync.conf` and the default exclude file for the `.claude` harness. Prompts before overwriting an existing config.

```bash
pisync init
```

---

### `pisync add-node <name> <host> [user] [port]`

Registers a peer node and appends a `NODE_NN` entry to `pisync.conf`. Prompts to deploy SSH keys immediately.

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `name` | Yes | — | Identifier used in sync commands |
| `host` | Yes | — | IP address or hostname |
| `user` | No | `$USER` | SSH user on the remote node |
| `port` | No | `22` | SSH port |

All arguments are validated against shell metacharacters before being written to the config.

```bash
pisync add-node pi-workshop 192.168.1.101
pisync add-node pi-garden   192.168.1.102 cory 2222
```

---

### `pisync add-project <name> <path> [remote_path] [exclude_file]`

Registers a project to sync and appends a `PROJECT_NN` entry to `pisync.conf`.

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `name` | Yes | — | Identifier used in sync commands |
| `path` | Yes | — | Absolute local path |
| `remote_path` | No | same as `path` | Absolute path on remote nodes |
| `exclude_file` | No | `""` | Path to an rsync exclude pattern file |

```bash
pisync add-project hydromazing /home/pi/projects/hydromazing
pisync add-project nexus /home/pi/projects/nexus /home/pi/projects/nexus ~/.pisync/excludes/nexus.exclude
```

---

### `pisync keys <host> [user]`

Generates an Ed25519 SSH key pair (if none exists) and deploys it to the target host via `ssh-copy-id`. Logs the host key fingerprint before connecting.

```bash
pisync keys 192.168.1.101
pisync keys 192.168.1.101 cory
```

---

### `pisync install-service`

Installs and starts the PiSync systemd daemon. Writes:
- `/etc/systemd/system/pisync.service`
- `/etc/avahi/services/pisync.service` (if Avahi is installed)

Requires `sudo` privileges (the script prompts via `sudo tee`).

```bash
pisync install-service
```

---

## Sync commands

### `pisync sync [project] [node]`

Syncs in the direction set by `DEFAULT_DIRECTION` in config (default: `push`). Both arguments default to `all`.

```bash
pisync sync                            # all projects → all nodes
pisync sync claude-harness             # one project → all nodes
pisync sync claude-harness pi-workshop # one project → one node
```

---

### `pisync push [project] [node]`

Force push regardless of `DEFAULT_DIRECTION`. Local is authoritative.

```bash
pisync push
pisync push hydromazing
pisync push hydromazing pi-garden
```

---

### `pisync pull [project] [node]`

Force pull regardless of `DEFAULT_DIRECTION`. Remote is authoritative.

```bash
pisync pull
pisync pull claude-harness pi-workshop
```

---

### `pisync deploy [project]`

Pushes to all configured nodes with a dry-run preview and confirmation prompt. Also syncs the node list to remotes so they can run pisync independently. Reports successes and failures at the end.

```bash
pisync deploy              # deploy all projects
pisync deploy claude-harness  # deploy specific project
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

### `pisync dry-run [project] [node]`

Shows what rsync would transfer without making any changes. Sets `DRY_RUN=true` and calls `sync_project` — no files are modified.

```bash
pisync dry-run
pisync dry-run nexus pi-workshop
```

---

### `pisync watch <project>`

Watches the project's local directory with `inotifywait` and triggers a sync 2 seconds after the last file change (debounced). Runs in the foreground; press `Ctrl+C` to stop.

Requires `inotify-tools`.

```bash
pisync watch claude-harness
```

---

## Status commands

### `pisync status`

Shows connectivity status for all configured nodes (SSH reachable + uptime) and the last sync result for each project+node pair.

```bash
pisync status
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

### `pisync discover`

Scans the LAN for PiSync nodes using three methods in order:
1. Avahi/mDNS (`_pisync._tcp`)
2. TCP port-22 scan of the local `/24` subnet
3. Connectivity check of all configured `NODE_*` entries

```bash
pisync discover
```

---

### `pisync conflicts <project> <node>`

Compares file hashes between the local project directory and the remote node using `md5sum`. Reports the number of differing files and shows the first 20 lines of the diff.

```bash
pisync conflicts claude-harness pi-workshop
```

---

### `pisync log [lines]`

Tails the PiSync log file. Defaults to 50 lines.

```bash
pisync log
pisync log 200
```

Log location: `~/.pisync/pisync.log`

---

## Internal commands

### `pisync daemon`

Runs the sync loop used by the systemd service. Syncs all projects on the configured `DAEMON_INTERVAL`, with lock acquisition between cycles. Not typically invoked directly — use `pisync install-service` instead.

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
.pisync-local
```
