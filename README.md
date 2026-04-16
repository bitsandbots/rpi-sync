# rpi**Sync**

**LAN Project Synchronization for Raspberry Pi Networks**

CoreConduit Consulting Services | MIT License

---

rpi-sync keeps project directories synchronized across multiple Raspberry Pi nodes on your LAN. Built for offline-first, cloud-independent infrastructure — no external services, no accounts, no telemetry. Just rsync over SSH with zero-config mDNS discovery.

## What it does

- **Syncs project directories** across Pi nodes using rsync (efficient delta transfers — only changed bytes move)
- **Zero-config discovery** via Avahi/mDNS — nodes find each other automatically
- **Watch mode** with inotify — syncs within seconds of file changes
- **Conflict detection** before sync with hash-based manifest comparison
- **Systemd daemon** for background auto-sync on a configurable interval
- **Per-project exclude patterns** — keep node-specific state local
- **SSH key management** built in — one command to deploy keys

## Use cases

| Project | What syncs | What stays local |
|---------|-----------|-----------------|
| `.claude` harness | Prompts, templates, settings, scripts | Logs, PIDs, sockets |
| hydroMazing | Flask app, React PWA, configs | SQLite DB, sensor logs |
| NEXUS | Agent configs, rules, prompts | ChromaDB vectors, runtime state |
| Dotfiles | `.bashrc`, `.vimrc`, scripts | Machine-specific overrides |

## Quick start

### 1. Install on every node

```bash
git clone <your-repo>/rpi-sync.git
cd rpi-sync
chmod +x install.sh
sudo ./install.sh
```

### 2. Initialize

```bash
rpi-sync init
```

This creates `~/.rpi-sync/rpi-sync.conf` with a pre-configured entry for the `.claude` harness. Edit the file to uncomment nodes and add your projects.

### 3. Register peers

```bash
# On your primary node
rpi-sync add-node pi-workshop 192.168.1.101
rpi-sync add-node pi-garden   192.168.1.102
rpi-sync add-node pi-nexus    192.168.1.103
```

Each `add-node` prompts to deploy SSH keys immediately.

Alternatively, deploy SSH keys to all configured nodes at once:

```bash
./setup-ssh-keys.sh           # Interactive - prompts for password per node
./setup-ssh-keys.sh --check    # Verify SSH access only
./setup-ssh-keys.sh --node pi-workshop  # Setup specific node
```

### 4. Sync

```bash
# Sync everything to all nodes
rpi-sync sync

# Sync a specific project
rpi-sync sync claude-harness

# Sync to a specific node
rpi-sync sync claude-harness pi-workshop

# Pull from remote instead of push
rpi-sync pull claude-harness pi-workshop

# Preview without making changes
rpi-sync dry-run
```

### 5. Auto-sync

```bash
# Watch mode — syncs on file change (foreground)
rpi-sync watch claude-harness

# Daemon mode — syncs on interval (background service)
rpi-sync install-service
```

## Configuration

All configuration lives in `~/.rpi-sync/rpi-sync.conf`:

```bash
# ── Sync Settings ─────────────────────────────
DEFAULT_DIRECTION="push"       # push | pull
DAEMON_INTERVAL=300            # seconds between daemon syncs
WATCH_MODE=false               # auto-sync on file change
CONFLICT_STRATEGY="newest"     # newest | source | manual

# ── Projects ──────────────────────────────────
# Format: name|local_path|remote_path|exclude_file
PROJECT_01="claude-harness|/home/pi/.claude|/home/pi/.claude|~/.rpi-sync/excludes/claude-harness.exclude"
PROJECT_02="hydromazing|/home/pi/projects/hydromazing|/home/pi/projects/hydromazing|"

# ── Nodes ─────────────────────────────────────
# Format: name|host|user|port
NODE_01="pi-workshop|192.168.1.101|pi|22"
NODE_02="pi-garden|192.168.1.102|pi|22"
```

### Exclude files

Each project can have an exclude file with rsync patterns. The default for `.claude` is created at `~/.rpi-sync/excludes/claude-harness.exclude`:

```
# Runtime state (node-specific)
*.pid
*.sock
*.lock
logs/
*.log
tmp/
.rpi-sync-local
```

Create a `.rpi-sync-local` file inside any project directory to mark node-specific content that should never sync.

## Commands reference

| Command | Description |
|---------|-------------|
| `rpi-sync init` | Initialize rpi-sync on this node |
| `rpi-sync add-node <n> <host>` | Register a LAN peer |
| `rpi-sync add-project <n> <path>` | Register a project to sync |
| `rpi-sync keys <host> [user] [port]` | Deploy SSH keys to a node |
| `rpi-sync sync [project] [node]` | Sync now |
| `rpi-sync push [project] [node]` | Push to remote |
| `rpi-sync pull [project] [node]` | Pull from remote |
| `rpi-sync deploy [project]` | Push to all nodes + sync node list |
| `rpi-sync watch <project>` | Watch and auto-sync on change |
| `rpi-sync dry-run [project] [node]` | Preview sync without changes |
| `rpi-sync status` | Show node and sync status |
| `rpi-sync discover` | Scan LAN for rpi-sync nodes |
| `rpi-sync conflicts <project> <node>` | Check for file conflicts |
| `rpi-sync install-service` | Install systemd auto-sync daemon |
| `rpi-sync log [lines]` | View sync log |

## Architecture

```
┌─────────────────────┐     rsync/SSH      ┌─────────────────────┐
│  pi-primary         │◄──────────────────►│  pi-workshop        │
│  ├─ .claude/        │                    │  ├─ .claude/        │
│  ├─ hydromazing/    │     Avahi/mDNS     │  ├─ hydromazing/    │
│  └─ ~/.rpi-sync/      │◄──── discovery ───►│  └─ ~/.rpi-sync/      │
└─────────────────────┘                    └─────────────────────┘
         ▲                                          ▲
         │            rsync/SSH                     │
         └──────────────┬──────────────────────────┘
                        │
               ┌────────┴────────┐
               │  pi-garden      │
               │  ├─ .claude/    │
               │  └─ ~/.rpi-sync/  │
               └─────────────────┘
```

- **No central server** — any node can push or pull from any other
- **rsync checksums** — only changed bytes transfer, not full files
- **SSH transport** — encrypted, authenticated, uses your existing keys
- **Avahi/mDNS** — nodes advertise `_rpi-sync._tcp` for automatic discovery
- **inotify watch** — file change triggers sync within 2s (debounced)
- **Systemd timer** — configurable interval polling as alternative to watch

## Adding a new project

```bash
# Register the project
rpi-sync add-project dotfiles ~/.dotfiles

# Create an exclude file (optional)
cat > ~/.rpi-sync/excludes/dotfiles.exclude << 'EOF'
.local-machine
*.bak
EOF

# Test with dry-run
rpi-sync dry-run dotfiles

# Sync
rpi-sync sync dotfiles
```

## Troubleshooting

**"Permission denied" on sync**
→ Run `rpi-sync keys <host>` to deploy SSH keys
→ If keys are deployed but still failing, check if your SSH key has a **passphrase**:
  ```bash
  ssh -vvv -o BatchMode=yes user@host 'hostname' 2>&1 | grep passphrase
  ```
  If you see `read_passphrase: can't open /dev/tty`, your key is passphrase-protected.
  rpi-sync requires a **passphrase-less key** for BatchMode SSH:
  ```bash
  # Create a dedicated rpi-sync key
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_rpi-sync -N ""

  # Re-run setup to deploy and configure
  ./setup-ssh-keys.sh
  ```

**"No rpi-sync nodes discovered"**
→ Check Avahi: `avahi-browse -t -r _rpi-sync._tcp`
→ Or add nodes manually: `rpi-sync add-node <n> <ip>`

**Sync is slow**
→ rsync uses checksums by default; first sync transfers everything, subsequent syncs only transfer deltas

**Conflicts detected**
→ Run `rpi-sync conflicts <project> <node>` to see which files differ
→ Resolve manually, then `rpi-sync push` or `rpi-sync pull` to establish source of truth

## Development

### Running tests

```bash
# Install test framework
sudo apt install bats shellcheck

# Run all tests
./tests/run_tests.sh

# Run specific test file
./tests/run_tests.sh discovery
./tests/run_tests.sh deploy
./tests/run_tests.sh connection

# Verbose output
./tests/run_tests.sh --verbose
```

The test suite covers:
- Node discovery and config parsing
- Deploy workflow and sync operations
- SSH/rsync connection handling
- Lock management and state files

## License

MIT — CoreConduit Consulting Services
