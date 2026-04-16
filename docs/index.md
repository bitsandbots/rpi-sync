# rpi-sync Documentation

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
rpi-sync init

# Add a peer
rpi-sync add-node pi-workshop 192.168.1.101

# Sync
rpi-sync sync
rpi-sync pull claude-harness pi-workshop
rpi-sync dry-run

# Watch for changes (foreground)
rpi-sync watch claude-harness

# Install background daemon
rpi-sync install-service

# Status
rpi-sync status
rpi-sync log
```
