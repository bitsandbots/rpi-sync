# rpi-sync — Setup & Usage

## Installation

Run the installer on **every node** in your Pi network:

```bash
git clone <your-repo>/rpi-sync.git
cd rpi-sync
chmod +x install.sh
sudo ./install.sh
```

### Installer options

```bash
sudo ./install.sh                        # Install to /usr/local/bin (default)
./install.sh --prefix ~/.local           # Install to ~/.local/bin (no sudo needed)
./install.sh --check                     # Verify dependencies only, don't install
sudo ./install.sh --uninstall            # Remove the rpi-sync binary
```

The installer:
1. Detects the installed version — shows upgrade message if updating.
2. Checks `rsync`, `openssh-client/server` (required) and `avahi-utils`, `inotify-tools` (optional).
3. Installs missing required packages via `apt`.
4. Enables `sshd` and `avahi-daemon` if not already running.
5. Copies `rpi-sync` to `$INSTALL_DIR/rpi-sync` and installs exclude templates to `/usr/local/share/rpi-sync/excludes/`.
6. Verifies the installed binary runs and prints its version.

Verify:
```bash
rpi-sync --version   # rpi-sync v1.0.0
bash healthcheck.sh
```

## First-time setup on each node

### 1. Initialize

```bash
rpi-sync init
```

Creates `~/.rpi-sync/rpi-sync.conf` with a pre-configured entry for the `.claude` harness, and a default exclude file at `~/.rpi-sync/excludes/claude-harness.exclude`. Edit the config to uncomment nodes and add projects.

### 2. Register peer nodes

```bash
rpi-sync add-node pi-workshop 192.168.1.101
rpi-sync add-node pi-garden   192.168.1.102
```

Each `add-node` prompts to deploy SSH keys immediately. You can also deploy keys separately:

```bash
rpi-sync keys 192.168.1.101          # uses SYNC_USER from config
rpi-sync keys 192.168.1.101 cory     # explicit user
```

> **Note:** `add-node` validates the name, host, user, and port for shell metacharacters before writing to config. Names containing `$`, backticks, `()`, `|`, `&`, or `<>` are rejected.

### 3. Register projects

The default config includes the `.claude` harness. To add more:

```bash
rpi-sync add-project hydromazing /home/pi/projects/hydromazing
rpi-sync add-project nexus /home/pi/projects/nexus /home/pi/projects/nexus
```

Optionally create an exclude file:
```bash
cp templates/excludes/hydromazing.exclude ~/.rpi-sync/excludes/hydromazing.exclude
# edit as needed, then reference it in rpi-sync.conf:
# PROJECT_02="hydromazing|/home/pi/projects/hydromazing|/home/pi/projects/hydromazing|~/.rpi-sync/excludes/hydromazing.exclude"
```

### 4. Test with dry-run

```bash
rpi-sync dry-run                            # all projects, all nodes
rpi-sync dry-run claude-harness             # specific project
rpi-sync dry-run claude-harness pi-workshop # specific project + node
```

### 5. Sync

```bash
rpi-sync sync                               # all projects → all nodes (push)
rpi-sync sync claude-harness                # specific project → all nodes
rpi-sync sync claude-harness pi-workshop    # specific project → specific node
rpi-sync pull claude-harness pi-workshop    # pull from remote instead
```

## Configuration reference

All configuration lives in `~/.rpi-sync/rpi-sync.conf`. It is a bash file that is `source`d at runtime — do not add command substitutions or untrusted content.

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
PROJECT_01="claude-harness|/home/pi/.claude|/home/pi/.claude|/home/pi/.rpi-sync/excludes/claude-harness.exclude"
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
.rpi-sync-local     # always exclude the local-override marker file
```

Template exclude files for common CoreConduit projects are in `templates/excludes/`. Copy and customize:

```bash
cp templates/excludes/nexus.exclude ~/.rpi-sync/excludes/nexus.exclude
```

### `.rpi-sync-local` marker

Create a `.rpi-sync-local` file inside any directory to permanently exclude that directory from all syncs (it's in the built-in default excludes). Useful for marking machine-specific state directories.

## Auto-sync modes

### Watch mode (foreground)

Syncs within 2 seconds of any file change using inotify. Runs in the foreground:

```bash
rpi-sync watch claude-harness
# Press Ctrl+C to stop
```

Requires `inotify-tools`: `sudo apt install inotify-tools`

### Daemon mode (background service)

Polls and syncs all projects on a configurable interval. Managed by systemd:

```bash
rpi-sync install-service    # installs and starts the systemd unit
systemctl status rpi-sync
systemctl stop rpi-sync
journalctl -u rpi-sync -f   # follow logs
```

The daemon also registers an Avahi `_rpi-sync._tcp` mDNS service so other nodes can discover this one automatically.

To change the interval, edit `DAEMON_INTERVAL` in `rpi-sync.conf` and restart the service:
```bash
systemctl restart rpi-sync
```

## Status and diagnostics

```bash
rpi-sync status                           # node connectivity + last sync results
rpi-sync discover                         # scan LAN for rpi-sync nodes
rpi-sync conflicts claude-harness pi-workshop  # compare file hashes
rpi-sync log                              # last 50 log lines
rpi-sync log 200                          # last 200 log lines
```

Log file location: `~/.rpi-sync/rpi-sync.log`

## Troubleshooting

**"Permission denied" on sync**
```bash
rpi-sync keys <host>     # (re)deploy SSH key
```

**"No rpi-sync nodes discovered"**
```bash
avahi-browse -t -r _rpi-sync._tcp        # check Avahi directly
rpi-sync add-node <name> <ip>            # add node manually
```

**"Project not found" in watch mode**
Confirm the project name in `rpi-sync.conf` matches exactly what you pass to `rpi-sync watch`.

**Sync slow on first run**
Expected — rsync transfers everything on first sync. Subsequent syncs only transfer deltas (checksum-based).

**Conflicts detected**
```bash
rpi-sync conflicts <project> <node>      # see which files differ
# resolve manually, then:
rpi-sync push <project> <node>           # establish this node as source of truth
# or:
rpi-sync pull <project> <node>           # take remote as source of truth
```

**Daemon not starting**
```bash
bash healthcheck.sh                    # full diagnostic
journalctl -u rpi-sync --no-pager -n 50  # systemd logs
```

## Releasing

Use `release.sh` to build a versioned distribution package.

```bash
# Preview what the release would do (no changes made)
./release.sh 1.1.0 --dry-run

# Create the release
./release.sh 1.1.0
```

`release.sh` will:
1. Validate semver format and that the new version is greater than current.
2. Verify the git working tree is clean.
3. Bump `RPI_SYNC_VERSION` in the `rpi-sync` script and verify syntax.
4. Build `dist/rpi-sync-v1.1.0.tar.gz` containing `rpi-sync`, `install.sh`, `healthcheck.sh`, `README.md`, `LICENSE`, `templates/`, and `docs/`.
5. Generate `dist/rpi-sync-v1.1.0.tar.gz.sha256`.
6. Commit the version bump and create an annotated git tag `v1.1.0`.

After running:
```bash
git push && git push --tags
# Attach dist/rpi-sync-v1.1.0.tar.gz to the GitHub release for tag v1.1.0
```

The `dist/` directory is gitignored — release artifacts are not committed to the repo.
