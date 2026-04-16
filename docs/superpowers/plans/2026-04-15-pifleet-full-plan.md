# PiFleet Implementation Plan (Full Detail)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify PiSync (bash CLI), PiMonitor, and PiMonitor Hub into a single Python package.

**Architecture:** Python package with Click CLI, Flask web apps, core library modules. Single `fleet.yml` config.

**Tech Stack:** Python 3.13, Click, Flask, PyYAML, requests, pytest

---

## Phase 1: Core Foundation

### Task 1: Package Setup

**Files:**
- Create: `~/pifleet/pyproject.toml`
- Create: `~/pifleet/pifleet/__init__.py`
- Create: `~/pifleet/pifleet/core/__init__.py`
- Create: `~/pifleet/tests/__init__.py`
- Create: `~/pifleet/tests/conftest.py`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p ~/pifleet/pifleet/{core,hub,monitor}
mkdir -p ~/pifleet/tests/fixtures
mkdir -p ~/pifleet/templates/excludes
```

- [ ] **Step 2: Create pyproject.toml**

```toml
[project]
name = "pifleet"
version = "1.0.0"
description = "Unified fleet management for Raspberry Pi networks"
authors = [{ name = "CoreConduit Consulting Services" }]
license = { text = "MIT" }
requires-python = ">=3.11"
dependencies = [
    "click>=8.0",
    "flask>=3.0",
    "pyyaml>=6.0",
    "requests>=2.31",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-mock>=3.12",
    "ruff>=0.3",
]

[project.scripts]
pifleet = "pifleet.cli:main"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[tool.ruff]
line-length = 88
target-version = "py311"
```

- [ ] **Step 3: Create init files**

`~/pifleet/pifleet/__init__.py`:
```python
"""PiFleet - Unified fleet management for Raspberry Pi networks."""
__version__ = "1.0.0"
```

`~/pifleet/pifleet/core/__init__.py`:
```python
"""Core library modules for PiFleet."""
from pifleet.core.config import FleetConfig, Node, Project
from pifleet.core.state import StateManager
from pifleet.core.output import info, warn, error, step

__all__ = ["FleetConfig", "Node", "Project", "StateManager", "info", "warn", "error", "step"]
```

- [ ] **Step 4: Initialize git**

```bash
cd ~/pifleet && git init && git add . && git commit -m "feat: initial project structure"
```

---

### Task 2: Output Module

**Files:**
- Create: `~/pifleet/pifleet/core/output.py`
- Create: `~/pifleet/tests/test_output.py`

- [ ] **Step 1: Write failing test**

`~/pifleet/tests/test_output.py`:
```python
"""Tests for output module."""
import io
import sys
from pifleet.core.output import info, warn, error, step, set_json_mode, set_log_file


def test_info_prints_green_checkmark(capsys):
    """info() should print green checkmark."""
    info("Test message")
    captured = capsys.readouterr()
    assert "✓" in captured.out
    assert "Test message" in captured.out


def test_warn_prints_yellow_warning(capsys):
    """warn() should print yellow warning."""
    warn("Warning message")
    captured = capsys.readouterr()
    assert "⚠" in captured.out


def test_error_prints_red_x(capsys):
    """error() should print red X."""
    error("Error message")
    captured = capsys.readouterr()
    assert "✗" in captured.out


def test_step_prints_blue_arrow(capsys):
    """step() should print blue arrow."""
    step("Step message")
    captured = capsys.readouterr()
    assert "→" in captured.out


def test_json_mode_outputs_json(capsys):
    """In JSON mode, output should be JSON."""
    set_json_mode(True)
    info("Test message")
    captured = capsys.readouterr()
    import json
    data = json.loads(captured.out.strip())
    assert data["level"] == "info"
    assert data["message"] == "Test message"
    set_json_mode(False)
```

- [ ] **Step 2: Run test** → Should fail with ModuleNotFoundError

- [ ] **Step 3: Write implementation**

`~/pifleet/pifleet/core/output.py`:
```python
"""Output utilities with color support and JSON mode."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import TextIO | None

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"

_json_mode = False
_log_file: TextIO | None = None


def set_json_mode(enabled: bool) -> None:
    global _json_mode
    _json_mode = enabled


def set_log_file(path: Path | None) -> None:
    global _log_file
    if path is None:
        _log_file = None
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        _log_file = open(path, "a", encoding="utf-8")


def _log(level: str, message: str) -> None:
    if _log_file:
        timestamp = datetime.now(timezone.utc).isoformat()
        _log_file.write(f"{timestamp} [{level.upper()}] {message}\n")
        _log_file.flush()


def _output(symbol: str, color: str, level: str, message: str) -> None:
    if _json_mode:
        output = json.dumps({"level": level, "message": message})
        print(output)
    else:
        print(f"  {color}{symbol}{NC} {message}")
    _log(level, message)


def info(message: str) -> None:
    _output("✓", GREEN, "info", message)


def warn(message: str) -> None:
    _output("⚠", YELLOW, "warn", message)


def error(message: str) -> None:
    _output("✗", RED, "error", message)


def step(message: str) -> None:
    _output("→", BLUE, "step", message)
```

- [ ] **Step 4: Run tests** → Should pass
- [ ] **Step 5: Commit**

---

### Task 3: State Module

**Files:**
- Create: `~/pifleet/pifleet/core/state.py`
- Create: `~/pifleet/tests/test_state.py`

- [ ] **Step 1: Write failing test**

`~/pifleet/tests/test_state.py`:
```python
"""Tests for state module."""
from pathlib import Path
import pytest
from pifleet.core.state import StateManager, SyncRecord, SyncResult


def test_state_manager_creates_state_dir(tmp_path):
    """StateManager should create state directory."""
    state_dir = tmp_path / "state"
    sm = StateManager(state_dir=state_dir, log_file=tmp_path / "pifleet.log")
    assert state_dir.exists()


def test_record_sync_creates_file(tmp_path):
    """record_sync should create a state file."""
    state_dir = tmp_path / "state"
    sm = StateManager(state_dir=state_dir, log_file=tmp_path / "pifleet.log")
    result = SyncResult(success=True, direction="push", duration_seconds=4.5)
    sm.record_sync("testproject", "testnode.local", result)
    state_file = state_dir / "testproject_testnode.local.last"
    assert state_file.exists()


def test_last_sync_returns_record(tmp_path):
    """last_sync should return the most recent sync record."""
    state_dir = tmp_path / "state"
    sm = StateManager(state_dir=state_dir, log_file=tmp_path / "pifleet.log")
    result = SyncResult(success=True, direction="push", duration_seconds=4.5)
    sm.record_sync("testproject", "testnode.local", result)
    record = sm.last_sync("testproject", "testnode.local")
    assert record is not None
    assert record.project == "testproject"
    assert record.success is True


def test_acquire_lock_creates_lock_file(tmp_path):
    """acquire_lock should create lock file with PID."""
    state_dir = tmp_path / "state"
    lock_file = tmp_path / "pifleet.lock"
    sm = StateManager(state_dir=state_dir, log_file=tmp_path / "pifleet.log", lock_file=lock_file)
    result = sm.acquire_lock()
    assert result is True
    assert lock_file.exists()


def test_release_lock_removes_file(tmp_path):
    """release_lock should remove lock file."""
    state_dir = tmp_path / "state"
    lock_file = tmp_path / "pifleet.lock"
    sm = StateManager(state_dir=state_dir, log_file=tmp_path / "pifleet.log", lock_file=lock_file)
    sm.acquire_lock()
    sm.release_lock()
    assert not lock_file.exists()
```

- [ ] **Step 2: Run test** → Should fail
- [ ] **Step 3: Write implementation**

`~/pifleet/pifleet/core/state.py`:
```python
"""State management for PiFleet."""
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import TextIO


@dataclass
class SyncResult:
    success: bool
    direction: str
    duration_seconds: float
    error: str | None = None
    files_transferred: int = 0
    bytes_transferred: int = 0


@dataclass
class SyncRecord:
    timestamp: datetime
    project: str
    node: str
    success: bool
    direction: str
    duration_seconds: float


class StateManager:
    def __init__(
        self,
        state_dir: Path | None = None,
        log_file: Path | None = None,
        lock_file: Path | None = None,
    ):
        self.state_dir = state_dir or Path.home() / ".pifleet" / "state"
        self.log_file = log_file or Path.home() / ".pifleet" / "pifleet.log"
        self.lock_file = lock_file or Path.home() / ".pifleet" / "pifleet.lock"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        self._log_handle: TextIO | None = None

    def _get_log_handle(self) -> TextIO:
        if self._log_handle is None:
            self._log_handle = open(self.log_file, "a", encoding="utf-8")
        return self._log_handle

    def log(self, level: str, message: str) -> None:
        timestamp = datetime.now(timezone.utc).isoformat()
        handle = self._get_log_handle()
        handle.write(f"{timestamp} [{level.upper()}] {message}\n")
        handle.flush()

    def record_sync(self, project: str, node: str, result: SyncResult) -> None:
        timestamp = datetime.now(timezone.utc)
        safe_node = node.replace(".", "_").replace(":", "_")
        state_file = self.state_dir / f"{project}_{safe_node}.last"
        status = "success" if result.success else "failure"
        line = f"{timestamp.isoformat()}|{result.direction}|{result.duration_seconds:.1f}s|{status}"
        state_file.write_text(line + "\n")
        self.log("INFO", f"sync: {project} → {node} {result.direction} {result.duration_seconds:.1f}s {status}")

    def last_sync(self, project: str, node: str) -> SyncRecord | None:
        safe_node = node.replace(".", "_").replace(":", "_")
        state_file = self.state_dir / f"{project}_{safe_node}.last"
        if not state_file.exists():
            return None
        content = state_file.read_text().strip()
        if not content:
            return None
        try:
            parts = content.split("|")
            if len(parts) != 4:
                return None
            timestamp = datetime.fromisoformat(parts[0])
            direction = parts[1]
            duration = float(parts[2].rstrip("s"))
            success = parts[3] == "success"
            return SyncRecord(
                timestamp=timestamp,
                project=project,
                node=node,
                success=success,
                direction=direction,
                duration_seconds=duration,
            )
        except (ValueError, IndexError):
            return None

    def acquire_lock(self) -> bool:
        if self.lock_file.exists():
            try:
                pid = int(self.lock_file.read_text().strip())
                if os.path.exists(f"/proc/{pid}"):
                    return False
                self.lock_file.unlink()
            except (ValueError, OSError):
                self.lock_file.unlink()
        self.lock_file.write_text(str(os.getpid()))
        return True

    def release_lock(self) -> None:
        try:
            self.lock_file.unlink()
        except OSError:
            pass
```

- [ ] **Step 4: Run tests** → Should pass
- [ ] **Step 5: Commit**

---

### Task 4: Config Module

**Files:**
- Create: `~/pifleet/pifleet/core/config.py`
- Create: `~/pifleet/tests/test_config.py`
- Create: `~/pifleet/tests/fixtures/fleet_minimal.yml`
- Create: `~/pifleet/tests/fixtures/fleet_full.yml`

- [ ] **Step 1: Create fixtures**

`~/pifleet/tests/fixtures/fleet_minimal.yml`:
```yaml
pifleet:
  version: 1
  node_name: testnode
  sync_user: testuser

nodes:
  testnode:
    host: testnode.local
    user: testuser
    port: 22
    role: test
    groups: [test]
    services: []
    monitor_port: 8585

groups:
  test:
    description: Test group

projects: {}

sync:
  default_direction: push
  daemon_interval: 300
  conflict_strategy: newest
  default_excludes:
    - .git/objects
    - __pycache__

ssh:
  key_file: ~/.ssh/id_ed25519_pifleet
  connect_timeout: 10
  batch_mode: true
```

- [ ] **Step 2: Write failing test**

`~/pifleet/tests/test_config.py`:
```python
"""Tests for config module."""
from pathlib import Path
import pytest
from pifleet.core.config import FleetConfig, Node, Project


def test_load_minimal_config():
    config_path = Path(__file__).parent / "fixtures" / "fleet_minimal.yml"
    config = FleetConfig.load(config_path)
    assert config.node_name == "testnode"
    assert len(config.nodes) == 1


def test_resolve_targets_by_node():
    config_path = Path(__file__).parent / "fixtures" / "fleet_full.yml"
    config = FleetConfig.load(config_path)
    nodes = config.resolve_targets(["node1"])
    assert len(nodes) == 1
    assert nodes[0].name == "node1"


def test_config_missing_file():
    with pytest.raises(FileNotFoundError):
        FleetConfig.load(Path("/nonexistent/config.yml"))
```

- [ ] **Step 3: Run test** → Should fail
- [ ] **Step 4: Write implementation**

`~/pifleet/pifleet/core/config.py`:
```python
"""Configuration management for PiFleet."""
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
import yaml


@dataclass
class Node:
    name: str
    host: str
    user: str
    port: int = 22
    role: str = ""
    groups: list[str] = field(default_factory=list)
    services: list[str] = field(default_factory=list)
    monitor_port: int = 8585

    @classmethod
    def from_dict(cls, name: str, data: dict[str, Any]) -> "Node":
        return cls(
            name=name,
            host=data["host"],
            user=data["user"],
            port=data.get("port", 22),
            role=data.get("role", ""),
            groups=data.get("groups", []),
            services=data.get("services", []),
            monitor_port=data.get("monitor_port", 8585),
        )


@dataclass
class Project:
    name: str
    local_path: Path
    remote_path: Path
    targets: list[str]
    exclude_file: Path | None = None

    @classmethod
    def from_dict(cls, name: str, data: dict[str, Any]) -> "Project":
        return cls(
            name=name,
            local_path=Path(data["local_path"]).expanduser(),
            remote_path=Path(data["remote_path"]).expanduser(),
            targets=data.get("targets", []),
            exclude_file=Path(data["exclude_file"]).expanduser() if data.get("exclude_file") else None,
        )


@dataclass
class GroupDef:
    name: str
    description: str = ""


@dataclass
class SyncSettings:
    default_direction: str = "push"
    daemon_interval: int = 300
    conflict_strategy: str = "newest"
    default_excludes: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "SyncSettings":
        return cls(
            default_direction=data.get("default_direction", "push"),
            daemon_interval=data.get("daemon_interval", 300),
            conflict_strategy=data.get("conflict_strategy", "newest"),
            default_excludes=data.get("default_excludes", []),
        )


@dataclass
class SSHSettings:
    key_file: Path = Path("~/.ssh/id_ed25519_pifleet")
    connect_timeout: int = 10
    batch_mode: bool = True

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "SSHSettings":
        return cls(
            key_file=Path(data.get("key_file", "~/.ssh/id_ed25519_pifleet")).expanduser(),
            connect_timeout=data.get("connect_timeout", 10),
            batch_mode=data.get("batch_mode", True),
        )


@dataclass
class FleetConfig:
    node_name: str
    sync_user: str
    nodes: dict[str, Node]
    groups: dict[str, GroupDef]
    projects: dict[str, Project]
    sync: SyncSettings
    ssh: SSHSettings
    version: int = 1

    @classmethod
    def load(cls, path: Path) -> "FleetConfig":
        if not path.exists():
            raise FileNotFoundError(f"Config file not found: {path}")
        try:
            data = yaml.safe_load(path.read_text())
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML in config file: {e}") from e

        if not data or "pifleet" not in data:
            raise ValueError("Config file missing 'pifleet' section")

        pifleet = data["pifleet"]
        nodes = {name: Node.from_dict(name, nd) for name, nd in data.get("nodes", {}).items()}
        groups = {name: GroupDef(name=name, description=gd.get("description", "")) for name, gd in data.get("groups", {}).items()}
        projects = {name: Project.from_dict(name, pd) for name, pd in data.get("projects", {}).items()}
        sync = SyncSettings.from_dict(data.get("sync", {}))
        ssh = SSHSettings.from_dict(data.get("ssh", {}))

        return cls(
            node_name=pifleet.get("node_name", ""),
            sync_user=pifleet.get("sync_user", ""),
            nodes=nodes,
            groups=groups,
            projects=projects,
            sync=sync,
            ssh=ssh,
            version=pifleet.get("version", 1),
        )

    def save(self, path: Path) -> None:
        data = {
            "pifleet": {"version": self.version, "node_name": self.node_name, "sync_user": self.sync_user},
            "nodes": {name: {"host": n.host, "user": n.user, "port": n.port, "role": n.role, "groups": n.groups, "services": n.services, "monitor_port": n.monitor_port} for name, n in self.nodes.items()},
            "groups": {name: {"description": g.description} for name, g in self.groups.items()},
            "projects": {name: {"local_path": str(p.local_path), "remote_path": str(p.remote_path), "exclude_file": str(p.exclude_file) if p.exclude_file else None, "targets": p.targets} for name, p in self.projects.items()},
            "sync": {"default_direction": self.sync.default_direction, "daemon_interval": self.sync.daemon_interval, "conflict_strategy": self.sync.conflict_strategy, "default_excludes": self.sync.default_excludes},
            "ssh": {"key_file": str(self.ssh.key_file), "connect_timeout": self.ssh.connect_timeout, "batch_mode": self.ssh.batch_mode},
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.dump(data, default_flow_style=False, sort_keys=False))

    def resolve_targets(self, targets: list[str]) -> list[Node]:
        resolved = []
        for target in targets:
            if target in self.nodes:
                resolved.append(self.nodes[target])
            elif target in self.groups:
                for node in self.nodes.values():
                    if target in node.groups and node not in resolved:
                        resolved.append(node)
        return resolved

    def nodes_for_project(self, project: Project) -> list[Node]:
        return self.resolve_targets(project.targets)
```

- [ ] **Step 5: Run tests** → Should pass
- [ ] **Step 6: Commit**

---

## Remaining Tasks (Summary)

Tasks 5-15 follow the same TDD pattern. Key modules:

- **Task 5:** Services module (systemctl operations)
- **Task 6:** SSH module (key lifecycle, config management)
- **Task 7:** Sync module (rsync wrapper)
- **Task 8:** Nodes module (fleet health, exec, update)
- **Task 9:** Discovery module (avahi, subnet scan)
- **Task 10:** Daemon module (periodic sync)
- **Task 11:** CLI entry point (Click commands)
- **Task 12:** Monitor Flask app
- **Task 13:** Hub Flask app
- **Task 14:** Migration module
- **Task 15:** Install script

---

## Execution Options

1. **Subagent-Driven (recommended)** - Fresh subagent per task, review between tasks
2. **Inline Execution** - Execute in this session with checkpoints

**Which approach?**
