# PiFleet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify PiSync (bash CLI), PiMonitor, and PiMonitor Hub into a single Python package with shared core library, YAML config, and automatic SSH key management.

**Architecture:** Python package with Click CLI, Flask web apps (monitor + hub), and a core library of modules (config, nodes, sync, ssh, discovery, services, state, daemon, output). Single `fleet.yml` config replaces `pisync.conf` and `hub_nodes.json`.

**Tech Stack:** Python 3.13, Click (CLI), Flask (web), PyYAML (config), requests (HTTP), pytest (testing)

---

## File Structure

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

## Phase 1: Core Foundation

### Task 1: Package Setup and Project Structure

**Files:**
- Create: `~/pifleet/pyproject.toml`
- Create: `~/pifleet/pifleet/__init__.py`
- Create: `~/pifleet/pifleet/core/__init__.py`
- Create: `~/pifleet/tests/__init__.py`
- Create: `~/pifleet/tests/conftest.py`

- [ ] **Step 1: Create project directory structure**

- [ ] **Step 2: Create pyproject.toml**

- [ ] **Step 3: Create package init files**

- [ ] **Step 4: Initialize git repository**

---

### Task 2: Output Module

**Files:**
- Create: `~/pifleet/pifleet/core/output.py`
- Create: `~/pifleet/tests/test_output.py`

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 3: State Module

**Files:**
- Create: `~/pifleet/pifleet/core/state.py`
- Create: `~/pifleet/tests/test_state.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 4: Config Module - Dataclasses

**Files:**
- Create: `~/pifleet/pifleet/core/config.py`
- Create: `~/pifleet/tests/test_config.py`
- Create: `~/pifleet/tests/fixtures/fleet_minimal.yml`
- Create: `~/pifleet/tests/fixtures/fleet_full.yml`

- [ ] **Step 1: Create test fixtures**
- [ ] **Step 2: Write the failing test**
- [ ] **Step 3: Run test to verify it fails**
- [ ] **Step 4: Write minimal implementation**
- [ ] **Step 5: Run test to verify it passes**
- [ ] **Step 6: Commit**

---

### Task 5: Services Module

**Files:**
- Create: `~/pifleet/pifleet/core/services.py`
- Create: `~/pifleet/tests/test_services.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

## Phase 2: SSH Management

### Task 6: SSH Module

**Files:**
- Create: `~/pifleet/pifleet/core/ssh.py`
- Create: `~/pifleet/tests/test_ssh.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

## Phase 3: Sync Engine

### Task 7: Sync Module

**Files:**
- Create: `~/pifleet/pifleet/core/sync.py`
- Create: `~/pifleet/tests/test_sync.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

## Phase 4: Fleet Management

### Task 8: Nodes Module

**Files:**
- Create: `~/pifleet/pifleet/core/nodes.py`
- Create: `~/pifleet/tests/test_nodes.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 9: Discovery Module

**Files:**
- Create: `~/pifleet/pifleet/core/discovery.py`
- Create: `~/pifleet/tests/test_discovery.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 10: Daemon Module

**Files:**
- Create: `~/pifleet/pifleet/core/daemon.py`
- Create: `~/pifleet/tests/test_daemon.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

## Phase 5: CLI Commands

### Task 11: CLI Entry Point

**Files:**
- Create: `~/pifleet/pifleet/cli.py`
- Create: `~/pifleet/tests/test_cli.py**

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Write minimal implementation**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

## Phase 6: Monitor Refactor

### Task 12: Monitor Flask App

**Files:**
- Create: `~/pifleet/pifleet/monitor/__init__.py`
- Create: `~/pifleet/pifleet/monitor/app.py`
- Create: `~/pifleet/pifleet/monitor/routes.py**

- [ ] **Step 1: Write minimal monitor app**
- [ ] **Step 2: Test monitor app**
- [ ] **Step 3: Commit**

---

## Phase 7: Hub Refactor

### Task 13: Hub Flask App

**Files:**
- Create: `~/pifleet/pifleet/hub/__init__.py`
- Create: `~/pifleet/pifleet/hub/app.py`
- Create: `~/pifleet/pifleet/hub/routes.py**

- [ ] **Step 1: Write minimal hub app**
- [ ] **Step 2: Test hub app**
- [ ] **Step 3: Commit**

---

## Phase 8: Migration & Install

### Task 14: Migration Module

**Files:**
- Create: `~/pifleet/pifleet/core/migration.py`
- Create: `~/pifleet/tests/test_migration.py`
- Create: `~/pifleet/tests/fixtures/pisync_legacy.conf`
- Create: `~/pifleet/tests/fixtures/hub_nodes_legacy.json**

- [ ] **Step 1: Create legacy fixtures**
- [ ] **Step 2: Write the failing test**
- [ ] **Step 3: Run test to verify it fails**
- [ ] **Step 4: Write minimal implementation**
- [ ] **Step 5: Run test to verify it passes**
- [ ] **Step 6: Commit**

---

### Task 15: Install Script

**Files:**
- Create: `~/pifleet/install.sh`

- [ ] **Step 1: Write install script**
- [ ] **Step 2: Make executable**
- [ ] **Step 3: Commit**

---

## Self-Review Checklist

After completing all tasks, verify:

- [ ] **Spec coverage:** Each section of the design spec has corresponding tasks
- [ ] **All tests pass:** `pytest tests/ -v` completes with all tests passing
- [ ] **CLI works:** `pifleet --help` shows help
- [ ] **Config loads:** `pifleet status` works with a valid fleet.yml
- [ ] **No placeholders:** No "TODO" or "TBD" in implementation
- [ ] **Type consistency:** All type hints match across modules

---

## Execution Handoff

**Plan complete.**

**Two execution options:**

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
