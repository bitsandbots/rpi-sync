# PiSync Documentation

LAN Project Synchronization for Raspberry Pi Networks — CoreConduit Consulting Services

---

## Docs

| Document | Audience | Contents |
|----------|----------|----------|
| [Overview](overview.md) | Everyone | Purpose, goals, use cases |
| [Architecture](architecture.md) | Operators / Contributors | Topology, data flow, code structure, security model |
| [Tech Stack](tech-stack.md) | Operators / Contributors | Dependencies, system requirements, platform notes |
| [Setup & Usage](setup.md) | Operators | Installation, configuration, sync modes, troubleshooting |
| [CLI Reference](cli-reference.md) | Operators | All commands, arguments, rsync flags |
| [Internals](internals.md) | Contributors | Function-level documentation, extension guide |

## Quick reference

```bash
# Install (run on each node)
sudo ./install.sh

# Initialize this node
pisync init

# Add a peer
pisync add-node pi-workshop 192.168.1.101

# Sync
pisync sync
pisync pull claude-harness pi-workshop
pisync dry-run

# Watch for changes (foreground)
pisync watch claude-harness

# Install background daemon
pisync install-service

# Status
pisync status
pisync log
```
