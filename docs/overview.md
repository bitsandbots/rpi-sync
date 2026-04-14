# PiSync — Overview

## Purpose

PiSync keeps project directories synchronized across multiple Raspberry Pi nodes on a LAN. It is built for offline-first, cloud-independent infrastructure — no external services, no accounts, no telemetry. All transfers happen over rsync/SSH between nodes you own.

## Goals

| Goal | How it's achieved |
|------|------------------|
| Zero external dependencies | rsync + SSH + Avahi — all standard Debian packages |
| Offline-first | No internet required; mDNS discovery works on isolated LANs |
| Efficient transfers | rsync `--checksum` — only changed bytes move, not whole files |
| Node-specific state stays local | Per-project exclude files; `.pisync-local` marker file |
| Simple ops | Single bash script, one config file, systemd integration |

## What it syncs

PiSync is project-agnostic. Common use cases:

| Project | What syncs | What stays local |
|---------|-----------|-----------------|
| `.claude` harness | Prompts, templates, settings, scripts | Logs, PIDs, sockets |
| hydroMazing | Flask app, React PWA, configs | SQLite DB, sensor logs |
| NEXUS platform | Agent configs, rules, prompts | ChromaDB vectors, runtime state |
| Dotfiles | `.bashrc`, `.vimrc`, scripts | Machine-specific overrides |

## Design philosophy

- **Any node can be source or destination** — push or pull, no fixed primary.
- **Conflicts surface explicitly** — hash-based manifest comparison before sync; no silent overwrites.
- **Watch mode over polling** — inotify triggers sync within 2 seconds of a file change; no unnecessary transfers.
- **The config file is the source of truth** — no hidden state except sync history in `~/.pisync/state/`.
