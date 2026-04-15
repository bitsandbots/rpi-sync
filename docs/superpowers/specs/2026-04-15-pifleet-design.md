# PiFleet Design Spec

**Date:** 2026-04-15
**Status:** Approved
**Replaces:** PiSync (bash CLI), PiMonitor (standalone), PiMonitor Hub (standalone)

---

## Overview

PiFleet is a single Python CLI that unifies file sync (PiSync), node monitoring (PiMonitor), and fleet orchestration (from the CoreConduit Pi Fleet Communications Plan) into one tool with a shared core library and YAML-based fleet configuration.

### Goals

1. Replace three separate tools (PiSync, PiMonitor, PiMonitor Hub) with one cohesive package
2. Add fleet-aware orchestration: health checks, service management, remote exec, rolling updates
3. Automatic SSH key lifecycle — users never manually manage keys
4. Single YAML config (`fleet.yml`) replaces `pisync.conf` and `hub_nodes.json`
5. Shared core library used by both CLI and web dashboard

### Non-Goals

- Git bare repo management (Layer 3 from communications plan — separate concern)
- NEXUS integration (future, after pifleet stabilizes)
- Ansible adoption (pifleet replaces the need for Ansible in this fleet)
- Multi-user / RBAC (single-user fleet management)

---

## Architecture

```
pifleet CLI  ─┐
              ├──→  pifleet/core/ (config, nodes, sync, ssh, discovery, services, state)
Hub web UI   ─┘         │
                         ├── fleet.yml (single config, shared)
                         ├── SSH transport (CLI + daemon)
                         └── HTTP transport (Hub → Monitor polling)

Each managed node runs:
  pifleet-monitor.service (:8585) — local system metrics API

Control node additionally runs:
  pifleet-hub.service (:8686) — fleet dashboard, polls monitors
  pifleet-sync.service — periodic file sync daemon
```

---

## Package Structure

```
~/pifleet/
├── pyproject.toml
├── pifleet/
│   ├── __init__.py
│   ├── cli.py                      # Click CLI entry point
│   ├── core/
│   │   ├── __init__.py
│   │   ├── config.py               # fleet.yml parser → typed dataclasses
│   │   ├── nodes.py                # FleetManager: health, services, exec, update
│   │   ├── sync.py                 # SyncEngine: rsync, deploy, watch, conflicts
│   │   ├── discovery.py            # Avahi + subnet scan + HTTP ping
│   │   ├── ssh.py                  # SSHManager: key lifecycle, config, deploy
│   │   ├── services.py             # systemctl operations across nodes
│   │   ├── state.py                # State files, lock, logging
│   │   ├── daemon.py               # SyncDaemon: periodic sync loop
│   │   └── output.py               # info/warn/error/step + --json support
│   ├── hub/
│   │   ├── __init__.py
│   │   ├── app.py                  # Flask app (refactored from pi_monitor_hub.py)
│   │   ├── routes.py               # API routes using core/
│   │   └── templates/
│   │       └── hub.html
│   └── monitor/
│       ├── __init__.py
│       ├── app.py                  # Flask app (refactored from pi_monitor.py)
│       ├── routes.py               # /api/status, /api/services, etc.
│       └── templates/
│           └── index.html
├── templates/
│   └── excludes/                   # rsync exclude templates
├── tests/
│   ├── conftest.py
│   ├── test_config.py
│   ├── test_sync.py
│   ├── test_nodes.py
│   ├── test_ssh.py
│   ├── test_discovery.py
│   ├── test_services.py
│   ├── test_state.py
│   ├── test_migration.py
│   ├── test_cli.py
│   └── fixtures/
│       ├── fleet_minimal.yml
│       ├── fleet_full.yml
│       ├── pisync_legacy.conf
│       └── hub_nodes_legacy.json
└── docs/
```

---

## Config Format — fleet.yml

Single config file at `~/.pifleet/fleet.yml`. Read by CLI, Hub, and daemon.

```yaml
pifleet:
  version: 1
  node_name: rhubarb
  sync_user: coreconduit

nodes:
  rhubarb:
    host: rhubarb.local
    user: coreconduit
    port: 22
    role: nexus_core
    groups: [nexus, production]
    services: [nexus-api, ollama, chromadb, pi-monitor, pi-monitor-hub]
    monitor_port: 8585

  potpie:
    host: potpie.local
    user: coreconduit
    port: 22
    role: garden_bridge
    groups: [garden, production]
    services: [hydromazing-flask, serial-daemon, pi-monitor]
    monitor_port: 8585

groups:
  production:
    description: All production nodes
  nexus:
    description: NEXUS platform nodes
  garden:
    description: hydroMazing garden nodes

projects:
  claude-harness:
    local_path: ~/.claude
    remote_path: ~/.claude
    exclude_file: ~/.pifleet/excludes/claude-harness.exclude
    targets: [production]

  hydromazing:
    local_path: ~/hydromazing
    remote_path: ~/hydromazing
    exclude_file: ~/.pifleet/excludes/hydromazing.exclude
    targets: [garden]

  nexus:
    local_path: ~/nexus
    remote_path: ~/nexus
    exclude_file: ~/.pifleet/excludes/nexus.exclude
    targets: [nexus]

sync:
  default_direction: push
  daemon_interval: 300
  conflict_strategy: newest
  default_excludes:
    - .git/objects
    - __pycache__
    - "*.pyc"
    - node_modules
    - .DS_Store
    - "*.swp"
    - "*.swo"
    - .pisync-local

ssh:
  key_file: ~/.ssh/id_ed25519_pifleet
  connect_timeout: 10
  batch_mode: true
```

### Key properties

- Nodes have `groups` and `role` for targeting
- Projects have `targets` — sync only to relevant groups/nodes
- Services declared per-node — fleet knows what to check
- SSH key path is explicit and separate from personal keys
- `version: 1` field for future config format migrations

---

## Automatic SSH Key Management

SSH is fully automatic. No separate scripts, no manual key generation.

### Lifecycle

Any `pifleet` command that needs SSH:

1. **Key exists?** No → generate ed25519 at `ssh.key_file`, passphrase-less, comment `pifleet@{hostname}`
2. **Passphrase check:** If key has passphrase and ssh-agent doesn't have it loaded, warn with specific guidance
3. **~/.ssh/config:** Regenerate the pifleet-managed block with all fleet node hosts
4. **Per-node test:** `ssh -o BatchMode=yes node 'true'` — if fails and interactive terminal, offer one-time password deployment

### SSH config management

```
# --- pifleet managed (do not edit) ---
Host rhubarb.local potpie.local keylime.local
    IdentityFile ~/.ssh/id_ed25519_pifleet
    IdentitiesOnly yes
    BatchMode yes
    ConnectTimeout 10
    ServerAliveInterval 60
# --- end pifleet ---
```

Only the marked block is touched. User's own SSH config entries are never modified. Block is regenerated whenever fleet.yml nodes change.

### CLI subcommands

```
pifleet keys status              # Key fingerprint, per-node auth status
pifleet keys deploy [target]     # Push key to node/group/all
pifleet keys rotate              # Generate new key, deploy to all, retire old
pifleet keys verify              # Test BatchMode SSH to all nodes
```

---

## CLI Command Map

```
pifleet
├── init                              # Bootstrap: fleet.yml, key, discover, deploy keys
│   └── --migrate                     # Import from pisync.conf + hub_nodes.json
├── status                            # Overview: this node, all nodes, last syncs
│
├── sync [project] [node]             # Sync per default_direction
│   ├── --push / --pull               # Override direction
│   ├── --dry-run                     # Preview only
│   ├── --group <name>                # Target a node group
│   ├── --watch                       # inotify auto-sync (foreground)
│   └── --daemon                      # Run as periodic sync daemon
│
├── deploy [project]                  # Dry-run → confirm → sync all targets → report
│
├── fleet
│   ├── health [--group] [--json]     # Uptime, CPU temp, RAM, disk, throttle
│   ├── services [--group] [--node]   # Service status across fleet
│   ├── exec <cmd> [--group] [--node] # Run command across targets
│   │   └── --parallel / --serial
│   ├── update [--group] [--reboot]   # Rolling apt upgrade (serial, one node at a time)
│   ├── discover                      # Avahi + subnet + HTTP scan
│   └── nodes                         # List nodes with groups, roles
│       ├── add <name> <host>         # Add to fleet.yml
│       └── remove <name>             # Remove from fleet.yml
│
├── keys
│   ├── status                        # Key + per-node auth status
│   ├── deploy [target]               # Push key
│   ├── rotate                        # New key, deploy, retire old
│   └── verify                        # Test all nodes
│
├── hub [--port N]                    # Start fleet dashboard (:8686)
├── monitor [--port N]                # Start local monitor (:8585)
│
├── install [--check] [--uninstall]   # Install deps, systemd services
├── log [lines]                       # Tail ~/.pifleet/pifleet.log
├── conflicts <project> <node>        # Hash-based diff check
└── --version / --help
```

### Universal targeting

`--group <name>` and `--node <name>` are consistent across all fleet commands. Groups resolve to their member nodes via `config.resolve_targets()`.

---

## Core Library

### config.py

```python
@dataclass
class Node:
    name: str
    host: str
    user: str
    port: int
    role: str
    groups: list[str]
    services: list[str]
    monitor_port: int

@dataclass
class Project:
    name: str
    local_path: Path
    remote_path: Path
    exclude_file: Path | None
    targets: list[str]

@dataclass
class FleetConfig:
    node_name: str
    sync_user: str
    nodes: dict[str, Node]
    groups: dict[str, GroupDef]
    projects: dict[str, Project]
    sync: SyncSettings
    ssh: SSHSettings

    @classmethod
    def load(cls, path: Path) -> "FleetConfig": ...
    def save(self, path: Path) -> None: ...
    def resolve_targets(self, targets: list[str]) -> list[Node]: ...
    def nodes_for_project(self, project: Project) -> list[Node]: ...
```

### ssh.py

```python
class SSHManager:
    def ensure_ready(self, node: Node) -> bool: ...
    def ensure_key_exists(self) -> Path: ...
    def update_ssh_config(self, nodes: list[Node]) -> None: ...
    def deploy_key(self, node: Node) -> bool: ...
    def verify_node(self, node: Node) -> SSHStatus: ...
    def rotate_keys(self, nodes: list[Node]) -> RotateResult: ...
    def detect_passphrase(self, key_path: Path) -> bool: ...
```

### nodes.py

```python
@dataclass
class NodeHealth:
    node: Node
    reachable: bool
    uptime: str
    cpu_temp: float
    ram_free_mb: int
    ram_total_mb: int
    disk_pct: int
    throttled: str
    services: dict[str, str]

class FleetManager:
    def health(self, targets: list[Node]) -> list[NodeHealth]: ...
    def services(self, targets: list[Node]) -> dict[str, dict[str, str]]: ...
    def exec(self, cmd: str, targets: list[Node], parallel: bool = True) -> dict[str, ExecResult]: ...
    def update(self, targets: list[Node], reboot: bool = False) -> dict[str, UpdateResult]: ...
```

### sync.py

```python
class SyncEngine:
    def sync_project(self, project: Project, node: Node,
                     direction: str = "push", dry_run: bool = False) -> SyncResult: ...
    def deploy(self, project: Project | None = None) -> DeployResult: ...
    def watch(self, project: Project) -> None: ...
    def check_conflicts(self, project: Project, node: Node) -> list[ConflictFile]: ...
    def build_rsync_args(self, project: Project) -> list[str]: ...
```

### state.py

```python
class StateManager:
    def record_sync(self, project: str, node: str, result: SyncResult) -> None: ...
    def last_sync(self, project: str, node: str) -> SyncRecord | None: ...
    def all_syncs(self) -> list[SyncRecord]: ...
    def acquire_lock(self) -> bool: ...
    def release_lock(self) -> None: ...
    def log(self, level: str, msg: str) -> None: ...
```

### output.py

```python
def info(msg: str) -> None: ...     # green checkmark — prints + logs
def warn(msg: str) -> None: ...     # yellow warning
def error(msg: str) -> None: ...    # red X
def step(msg: str) -> None: ...     # blue arrow
```

All commands support `--json` flag for machine-readable output.

### daemon.py

```python
class SyncDaemon:
    def run(self) -> None:
        """Periodic sync loop. Acquires lock, syncs projects to their
        target nodes only, releases lock, sleeps daemon_interval."""
```

---

## Hub & Monitor Integration

### Monitor (per-node, :8585) — minimal refactor

- Split `pi_monitor.py` (800 lines) into `app.py` + `routes.py`
- Reads `fleet.yml` only for this node's `services` list (falls back to env vars)
- Replaces `services.json` persistence — services declared in `fleet.yml`
- API unchanged — existing Hub polling works during migration
- Launched via `pifleet monitor` or standalone

### Hub (fleet dashboard, :8686) — significant refactor

- Replaces `hub_nodes.json` with `fleet.yml` via `core/config.py`
- Uses `core/discovery.py` and `core/nodes.py` instead of own implementations
- Gains group/role awareness — UI can filter by group
- Hot-reloads `fleet.yml` on mtime change (checked each poll cycle)

New Hub API routes:

```
GET  /api/fleet/groups              # Groups with member nodes
GET  /api/fleet/projects            # Sync projects + last-sync status
GET  /api/fleet/health?group=garden # Health filtered by group
POST /api/fleet/sync/<project>      # Trigger sync from web UI
GET  /api/fleet/config              # Current fleet.yml (read-only)
```

Existing routes (`/api/fleet`, `/api/nodes/*`, `/api/discover`) preserved for compatibility.

---

## Systemd Services

`pifleet install` generates and enables:

| Service | Port | Where | Replaces |
|---|---|---|---|
| `pifleet-sync.service` | — | All nodes | `pisync.service` |
| `pifleet-monitor.service` | 8585 | All nodes | `pi-monitor.service` |
| `pifleet-hub.service` | 8686 | Control node only | `pi-monitor-hub.service` |

Control node detected by matching `pifleet.node_name` in fleet.yml.

Avahi mDNS service registered as `_pifleet._tcp` for discovery.

---

## Error Handling & Logging

### Log format

```
~/.pifleet/pifleet.log
2026-04-15T10:30:00+00:00 [INFO] sync: hydromazing → potpie.local push 4s success
```

### Error philosophy

- Node unreachable: report as down, continue to next node
- SSH key not deployed: auto-offer if interactive, log warning if daemon
- rsync fails: record failed state, report in summary, no auto-retry
- fleet.yml missing/invalid: fail fast with clear message
- Partial fleet failure: complete all reachable, report failures, exit code 1
- Lock held: report holder PID, detect and clean stale locks

### Exit codes

- 0: all succeeded
- 1: partial failure
- 2: total failure (config error, no nodes reachable, missing deps)

---

## Migration

`pifleet init --migrate` handles one-time transition:

1. Parse `~/.pisync/pisync.conf` → generate `fleet.yml` node/project entries
2. Merge `~/pi-monitor/hub/hub_nodes.json` → deduplicate by host
3. Copy `~/.pisync/state/*.last` → `~/.pifleet/state/`
4. Copy exclude files → `~/.pifleet/excludes/`
5. Stop and disable old systemd services
6. Generate and enable new systemd services

### Runtime directory

```
~/.pifleet/
├── fleet.yml
├── pifleet.log
├── pifleet.lock
├── state/
│   └── {project}_{host}.last
└── excludes/
```

---

## Dependencies

### Python (pip)

| Package | Purpose |
|---|---|
| `pyyaml>=6.0` | fleet.yml parsing |
| `click>=8.0` | CLI framework |
| `flask>=3.0` | Hub + Monitor web apps |
| `requests>=2.31` | Hub → Monitor HTTP polling |

### System (apt)

| Package | Required | Purpose |
|---|---|---|
| `rsync` | Yes | File sync engine |
| `openssh-client` | Yes | SSH connections |
| `openssh-server` | Yes | Accept SSH |
| `avahi-utils` | Optional | mDNS discovery |
| `inotify-tools` | Optional | Watch mode |

### Dev

| Package | Purpose |
|---|---|
| `pytest` | Test runner |
| `pytest-mock` | Mocking |
| `ruff` | Linting + formatting |

---

## Testing

### Unit tests (no real fleet needed)

- Config parsing, validation, group resolution
- rsync argument building, exclude handling
- SSH config block generation
- State file read/write, lock management
- systemctl output parsing
- Health check output parsing (mock SSH)
- Migration from legacy formats
- CLI argument handling

### Integration tests (marked, run manually)

- rsync between local directories
- SSH key deployment and BatchMode verification
- inotify watch + debounce
- PiMonitor HTTP polling
- Avahi/mDNS discovery

Test data uses `HARNESS_` prefix per project security rules.

---

## What Gets Retired

| Old | New | Fate |
|---|---|---|
| `pisync` (bash, 963 lines) | `pifleet sync` | Replaced entirely |
| `setup-ssh-keys.sh` | Auto SSH + `pifleet keys` | Replaced entirely |
| `healthcheck.sh` | `pifleet fleet health` + `pifleet keys verify` | Replaced entirely |
| `install.sh` | `pifleet install` | Replaced entirely |
| `release.sh` | Adapted for new package | Kept, modified |
| `pi_monitor.py` | `pifleet/monitor/` | Refactored in |
| `pi_monitor_hub.py` | `pifleet/hub/` | Refactored in |
| `pisync.conf` | `fleet.yml` | Migrated via `--migrate` |
| `hub_nodes.json` | `fleet.yml` | Migrated via `--migrate` |
| `services.json` | `fleet.yml` node services | Migrated via `--migrate` |
| bats test suite | pytest | Rewritten |

No backward compatibility maintained. Clean v2 with migration path.
