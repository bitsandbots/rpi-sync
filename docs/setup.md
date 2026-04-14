# PiSync — Setup & Usage

## Installation

Run the installer on **every node** in your Pi network:

```bash
git clone <your-repo>/pisync.git
cd pisync
chmod +x install.sh
sudo ./install.sh
```

The installer:
1. Checks for `rsync`, `openssh-client/server`, `avahi-utils`, `inotify-tools` — installs any that are missing.
2. Enables and starts `sshd` and `avahi-daemon` if not already running.
3. Copies `pisync` to `/usr/local/bin/pisync` with executable permissions.

Verify:
```bash
pisync --version   # PiSync v1.0.0
bash healthcheck.sh
```

## First-time setup on each node

### 1. Initialize

```bash
pisync init
```

Creates `~/.pisync/pisync.conf` with a pre-configured entry for the `.claude` harness, and a default exclude file at `~/.pisync/excludes/claude-harness.exclude`. Edit the config to uncomment nodes and add projects.

### 2. Register peer nodes

```bash
pisync add-node pi-workshop 192.168.1.101
pisync add-node pi-garden   192.168.1.102
```

Each `add-node` prompts to deploy SSH keys immediately. You can also deploy keys separately:

```bash
pisync keys 192.168.1.101          # uses SYNC_USER from config
pisync keys 192.168.1.101 cory     # explicit user
```

> **Note:** `add-node` validates the name, host, user, and port for shell metacharacters before writing to config. Names containing `$`, backticks, `()`, `|`, `&`, or `<>` are rejected.

### 3. Register projects

The default config includes the `.claude` harness. To add more:

```bash
pisync add-project hydromazing /home/pi/projects/hydromazing
pisync add-project nexus /home/pi/projects/nexus /home/pi/projects/nexus
```

Optionally create an exclude file:
```bash
cp templates/excludes/hydromazing.exclude ~/.pisync/excludes/hydromazing.exclude
# edit as needed, then reference it in pisync.conf:
# PROJECT_02="hydromazing|/home/pi/projects/hydromazing|/home/pi/projects/hydromazing|~/.pisync/excludes/hydromazing.exclude"
```

### 4. Test with dry-run

```bash
pisync dry-run                            # all projects, all nodes
pisync dry-run claude-harness             # specific project
pisync dry-run claude-harness pi-workshop # specific project + node
```

### 5. Sync

```bash
pisync sync                               # all projects → all nodes (push)
pisync sync claude-harness                # specific project → all nodes
pisync sync claude-harness pi-workshop    # specific project → specific node
pisync pull claude-harness pi-workshop    # pull from remote instead
```

## Configuration reference

All configuration lives in `~/.pisync/pisync.conf`. It is a bash file that is `source`d at runtime — do not add command substitutions or untrusted content.

### Global settings

```bash
NODE_NAME="pi-primary"         # This node's name (set automatically by init)
SYNC_USER="pi"                 # Default SSH user for all nodes

DEFAULT_DIRECTION="push"       # push | pull
DAEMON_INTERVAL=300            # Seconds between daemon syncs
WATCH_MODE=false               # Unused by CLI; watch mode is started explicitly
DRY_RUN=false                  # Set true to always preview without changing
CONFLICT_STRATEGY="newest"     # newest | source | manual (for future use)
```

### Project entries

```bash
# Format: name|local_path|remote_path|exclude_file
PROJECT_01="claude-harness|/home/pi/.claude|/home/pi/.claude|/home/pi/.pisync/excludes/claude-harness.exclude"
PROJECT_02="hydromazing|/home/pi/projects/hydromazing|/home/pi/projects/hydromazing|"
```

- `name` — identifier used in CLI commands
- `local_path` — absolute path on this node
- `remote_path` — absolute path on remote nodes (usually identical)
- `exclude_file` — path to rsync exclude pattern file; leave empty for no project-specific excludes

### Node entries

```bash
# Format: name|host|user|port
NODE_01="pi-workshop|192.168.1.101|pi|22"
NODE_02="pi-garden|192.168.1.102|pi|22"
```

- `name` — identifier used in CLI commands
- `host` — IP address or hostname
- `user` — SSH user on that node
- `port` — SSH port (default 22)

## Exclude files

Exclude files use standard rsync filter syntax. Each line is a pattern:

```
# Comments start with #
*.log             # exclude all .log files
data/             # exclude the data/ directory (trailing slash = dir only)
*.db              # exclude SQLite databases
.pisync-local     # always exclude the local-override marker file
```

Template exclude files for common CoreConduit projects are in `templates/excludes/`. Copy and customize:

```bash
cp templates/excludes/nexus.exclude ~/.pisync/excludes/nexus.exclude
```

### `.pisync-local` marker

Create a `.pisync-local` file inside any directory to permanently exclude that directory from all syncs (it's in the built-in default excludes). Useful for marking machine-specific state directories.

## Auto-sync modes

### Watch mode (foreground)

Syncs within 2 seconds of any file change using inotify. Runs in the foreground:

```bash
pisync watch claude-harness
# Press Ctrl+C to stop
```

Requires `inotify-tools`: `sudo apt install inotify-tools`

### Daemon mode (background service)

Polls and syncs all projects on a configurable interval. Managed by systemd:

```bash
pisync install-service    # installs and starts the systemd unit
systemctl status pisync
systemctl stop pisync
journalctl -u pisync -f   # follow logs
```

The daemon also registers an Avahi `_pisync._tcp` mDNS service so other nodes can discover this one automatically.

To change the interval, edit `DAEMON_INTERVAL` in `pisync.conf` and restart the service:
```bash
systemctl restart pisync
```

## Status and diagnostics

```bash
pisync status                           # node connectivity + last sync results
pisync discover                         # scan LAN for PiSync nodes
pisync conflicts claude-harness pi-workshop  # compare file hashes
pisync log                              # last 50 log lines
pisync log 200                          # last 200 log lines
```

Log file location: `~/.pisync/pisync.log`

## Troubleshooting

**"Permission denied" on sync**
```bash
pisync keys <host>     # (re)deploy SSH key
```

**"No PiSync nodes discovered"**
```bash
avahi-browse -t -r _pisync._tcp        # check Avahi directly
pisync add-node <name> <ip>            # add node manually
```

**"Project not found" in watch mode**
Confirm the project name in `pisync.conf` matches exactly what you pass to `pisync watch`.

**Sync slow on first run**
Expected — rsync transfers everything on first sync. Subsequent syncs only transfer deltas (checksum-based).

**Conflicts detected**
```bash
pisync conflicts <project> <node>      # see which files differ
# resolve manually, then:
pisync push <project> <node>           # establish this node as source of truth
# or:
pisync pull <project> <node>           # take remote as source of truth
```

**Daemon not starting**
```bash
bash healthcheck.sh                    # full diagnostic
journalctl -u pisync --no-pager -n 50  # systemd logs
```
