# Pi**Sync**

**LAN Project Synchronization for Raspberry Pi Networks**

CoreConduit Consulting Services | MIT License

---

PiSync keeps project directories synchronized across multiple Raspberry Pi nodes on your LAN. Built for offline-first, cloud-independent infrastructure — no external services, no accounts, no telemetry. Just rsync over SSH with zero-config mDNS discovery.

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
git clone <your-repo>/pisync.git
cd pisync
chmod +x install.sh
sudo ./install.sh
```

### 2. Initialize

```bash
pisync init
```

This creates `~/.pisync/pisync.conf` with a pre-configured entry for the `.claude` harness. Edit the file to uncomment nodes and add your projects.

### 3. Register peers

```bash
# On your primary node
pisync add-node pi-workshop 192.168.1.101
pisync add-node pi-garden   192.168.1.102
pisync add-node pi-nexus    192.168.1.103
```

Each `add-node` prompts to deploy SSH keys immediately.

### 4. Sync

```bash
# Sync everything to all nodes
pisync sync

# Sync a specific project
pisync sync claude-harness

# Sync to a specific node
pisync sync claude-harness pi-workshop

# Pull from remote instead of push
pisync pull claude-harness pi-workshop

# Preview without making changes
pisync dry-run
```

### 5. Auto-sync

```bash
# Watch mode — syncs on file change (foreground)
pisync watch claude-harness

# Daemon mode — syncs on interval (background service)
pisync install-service
```

## Configuration

All configuration lives in `~/.pisync/pisync.conf`:

```bash
# ── Sync Settings ─────────────────────────────
DEFAULT_DIRECTION="push"       # push | pull
DAEMON_INTERVAL=300            # seconds between daemon syncs
WATCH_MODE=false               # auto-sync on file change
CONFLICT_STRATEGY="newest"     # newest | source | manual

# ── Projects ──────────────────────────────────
# Format: name|local_path|remote_path|exclude_file
PROJECT_01="claude-harness|/home/pi/.claude|/home/pi/.claude|~/.pisync/excludes/claude-harness.exclude"
PROJECT_02="hydromazing|/home/pi/projects/hydromazing|/home/pi/projects/hydromazing|"

# ── Nodes ─────────────────────────────────────
# Format: name|host|user|port
NODE_01="pi-workshop|192.168.1.101|pi|22"
NODE_02="pi-garden|192.168.1.102|pi|22"
```

### Exclude files

Each project can have an exclude file with rsync patterns. The default for `.claude` is created at `~/.pisync/excludes/claude-harness.exclude`:

```
# Runtime state (node-specific)
*.pid
*.sock
*.lock
logs/
*.log
tmp/
.pisync-local
```

Create a `.pisync-local` file inside any project directory to mark node-specific content that should never sync.

## Commands reference

| Command | Description |
|---------|-------------|
| `pisync init` | Initialize PiSync on this node |
| `pisync add-node <n> <host>` | Register a LAN peer |
| `pisync add-project <n> <path>` | Register a project to sync |
| `pisync keys <host>` | Deploy SSH keys to a node |
| `pisync sync [project] [node]` | Sync now |
| `pisync push [project] [node]` | Push to remote |
| `pisync pull [project] [node]` | Pull from remote |
| `pisync watch <project>` | Watch and auto-sync on change |
| `pisync dry-run [project] [node]` | Preview sync without changes |
| `pisync status` | Show node and sync status |
| `pisync discover` | Scan LAN for PiSync nodes |
| `pisync conflicts <project> <node>` | Check for file conflicts |
| `pisync install-service` | Install systemd auto-sync daemon |
| `pisync log [lines]` | View sync log |

## Architecture

```
┌─────────────────────┐     rsync/SSH      ┌─────────────────────┐
│  pi-primary         │◄──────────────────►│  pi-workshop        │
│  ├─ .claude/        │                    │  ├─ .claude/        │
│  ├─ hydromazing/    │     Avahi/mDNS     │  ├─ hydromazing/    │
│  └─ ~/.pisync/      │◄──── discovery ───►│  └─ ~/.pisync/      │
└─────────────────────┘                    └─────────────────────┘
         ▲                                          ▲
         │            rsync/SSH                     │
         └──────────────┬──────────────────────────┘
                        │
               ┌────────┴────────┐
               │  pi-garden      │
               │  ├─ .claude/    │
               │  └─ ~/.pisync/  │
               └─────────────────┘
```

- **No central server** — any node can push or pull from any other
- **rsync checksums** — only changed bytes transfer, not full files
- **SSH transport** — encrypted, authenticated, uses your existing keys
- **Avahi/mDNS** — nodes advertise `_pisync._tcp` for automatic discovery
- **inotify watch** — file change triggers sync within 2s (debounced)
- **Systemd timer** — configurable interval polling as alternative to watch

## Adding a new project

```bash
# Register the project
pisync add-project dotfiles ~/.dotfiles

# Create an exclude file (optional)
cat > ~/.pisync/excludes/dotfiles.exclude << 'EOF'
.local-machine
*.bak
EOF

# Test with dry-run
pisync dry-run dotfiles

# Sync
pisync sync dotfiles
```

## Troubleshooting

**"Permission denied" on sync**
→ Run `pisync keys <host>` to deploy SSH keys

**"No PiSync nodes discovered"**
→ Check Avahi: `avahi-browse -t -r _pisync._tcp`
→ Or add nodes manually: `pisync add-node <n> <ip>`

**Sync is slow**
→ rsync uses checksums by default; first sync transfers everything, subsequent syncs only transfer deltas

**Conflicts detected**
→ Run `pisync conflicts <project> <node>` to see which files differ
→ Resolve manually, then `pisync push` or `pisync pull` to establish source of truth

## License

MIT — CoreConduit Consulting Services
