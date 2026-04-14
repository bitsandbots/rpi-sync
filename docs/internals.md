# PiSync — Internals

Module-level documentation for contributors or anyone extending PiSync.

---

## Global variables

Defined at the top of `pisync` and available throughout:

| Variable | Default | Description |
|----------|---------|-------------|
| `PISYNC_VERSION` | `"1.0.0"` | Semver string |
| `PISYNC_HOME` | `~/.pisync` | Runtime directory; override with env var |
| `PISYNC_CONF` | `$PISYNC_HOME/pisync.conf` | Config file path |
| `PISYNC_LOG` | `$PISYNC_HOME/pisync.log` | Append-only operation log |
| `PISYNC_LOCK` | `$PISYNC_HOME/pisync.lock` | PID lock file |
| `PISYNC_STATE` | `$PISYNC_HOME/state` | Directory of per-sync state files |

---

## Output / logging functions

```bash
log()   "$*"    # Writes to PISYNC_LOG with ISO timestamp — no stdout
info()  "✓ $*"  # Green — success or completion; also logs
warn()  "⚠ $*"  # Yellow — non-fatal issue; also logs
error() "✗ $*"  # Red — error; also logs
step()  "→ $*"  # Blue — in-progress action; also logs
```

All user-facing output goes through these functions. Never `echo` directly in command implementations.

---

## `init_dirs()`

```bash
init_dirs()
```

Creates `$PISYNC_HOME` and `$PISYNC_STATE` if they don't exist. Touches `$PISYNC_LOG`. Called unconditionally at the start of `main()` before command dispatch, so it is safe to call on every invocation.

---

## `load_config()`

```bash
load_config()
```

Sources `$PISYNC_CONF` into the current shell. Exits with error if the file doesn't exist. Must be called before any function that reads config variables (`SYNC_USER`, `DEFAULT_DIRECTION`, etc.).

**Side effect:** exports all variables defined in `pisync.conf` into the current process.

---

## `get_projects()` / `get_nodes()`

```bash
get_projects()   # outputs PROJECT_* values, one per line
get_nodes()      # outputs NODE_* values, one per line
```

Parse `$PISYNC_CONF` with `grep '^PROJECT_'` / `grep '^NODE_'` and strip surrounding quotes. Output is pipe-delimited:

```
name|local_path|remote_path|exclude_file
name|host|user|port
```

**Caller responsibility:** consume with process substitution `< <(get_projects)`, not a pipe, so loop variable assignments remain visible in the calling scope.

```bash
# Correct:
while IFS='|' read -r name lp rp ef; do
    ...
done < <(get_projects)

# Wrong — assignments in loop body are lost:
get_projects | while IFS='|' read -r name lp rp ef; do
    ...
done
```

---

## `acquire_lock()` / `release_lock()`

```bash
acquire_lock()   # returns 0 on success, 1 if another process holds the lock
release_lock()   # removes $PISYNC_LOCK
```

`acquire_lock` checks whether the PID in the lock file is still alive with `kill -0`. Stale locks (process gone) are silently removed and the lock re-acquired. In daemon mode, `release_lock` is called between each sleep interval so manual syncs can proceed without waiting.

Long-running commands should `trap 'release_lock; exit 0' SIGTERM SIGINT`.

---

## `validate_config_value(label, value)`

```bash
validate_config_value "name" "$name"
```

Rejects values containing shell metacharacters (`$`, `` ` ``, `(`, `)`, `;`, `|`, `&`, `<`, `>`) that could inject arbitrary code when the config file is sourced. Calls `exit 1` on failure. Must be called before any user-supplied value is appended to `$PISYNC_CONF`.

---

## `setup_keys(host, [user])`

```bash
setup_keys "192.168.1.101" "pi"
```

1. Generates `~/.ssh/id_ed25519` if no key exists.
2. Logs the remote host key fingerprint (via `ssh-keyscan | ssh-keygen -lf`) to `$PISYNC_LOG`.
3. Calls `ssh-copy-id -o StrictHostKeyChecking=no` to deploy the key.

The fingerprint log is the only audit trail for host key changes — review `pisync log` after adding new nodes.

---

## `build_rsync_args(project_name, exclude_file)`

```bash
rsync_args=$(build_rsync_args "claude-harness" "/home/pi/.pisync/excludes/claude-harness.exclude")
```

Returns a space-separated string of rsync flags. Appends `--exclude-from` only if `$exclude_file` is non-empty and the file exists. Default excludes (`.git/objects`, `node_modules`, etc.) are always appended last.

**Important:** the return value must be word-split when passed to rsync — use `$rsync_args` unquoted with `# shellcheck disable=SC2086`. This is intentional and documented in the source.

---

## `sync_project_to_node(name, local_path, remote_path, exclude_file, host, user, port, direction)`

```bash
sync_project_to_node "claude-harness" "/home/pi/.claude" "/home/pi/.claude" \
    "/home/pi/.pisync/excludes/claude-harness.exclude" \
    "192.168.1.101" "pi" "22" "push"
```

Core sync function. Constructs `src` and `dst` based on `direction` (`push` | `pull`), then calls rsync. On success or failure, writes a state file to `$PISYNC_STATE/${name}_${host}.last`.

Returns 1 if `$local_path` doesn't exist or if rsync exits non-zero.

---

## `sync_project(target_project, direction, target_node)`

```bash
sync_project "claude-harness" "push" "pi-workshop"
sync_project "all" "push" "all"
```

Orchestration layer. Iterates `get_projects` × `get_nodes` and calls `sync_project_to_node` for each matching combination. Both loops use process substitution so the `synced` counter is accurate. Warns if no project/node match was found.

---

## `check_conflicts(project_name, local_path, remote_path, host, user, port)`

```bash
check_conflicts "claude-harness" "/home/pi/.claude" "/home/pi/.claude" "192.168.1.101" "pi" "22"
```

Generates `md5sum` manifests locally and remotely (via SSH), sorts both, and diffs them. The remote path is escaped with `printf '%q'` before interpolation into the SSH command. Temp files are always cleaned up with `rm -f`.

Reports count of differing files and shows the first 20 lines of the raw diff.

---

## `watch_and_sync(project_name, local_path)`

```bash
watch_and_sync "claude-harness" "/home/pi/.claude"
```

Runs `inotifywait -m -r` on `$local_path`. For each event:

1. Kill the previous debounce background process (if still running).
2. Start a new background subshell: `sleep 2 && sync_project "$project_name"`.

The 2-second debounce ensures that a rapid series of saves (e.g. editor writing multiple files) results in a single sync, not many.

Events watched: `modify`, `create`, `delete`, `move`. Excludes: `.git/objects`, `node_modules`, `__pycache__`, `.swp` files.

---

## `discover_nodes()`

Three-phase discovery (see [architecture.md](architecture.md#node-discovery-fallback-chain)). The Avahi phase spawns `avahi-browse -t -r _pisync._tcp` and parses `hostname` lines. The subnet scan phase uses a background subshell per host (`timeout 1 bash -c "echo >/dev/tcp/$target/22"`) and a foreground spinner. Results are printed live; no state is written to disk.

---

## `cmd_daemon()`

```bash
cmd_daemon()
```

Infinite loop:
1. `acquire_lock` — skip this cycle if lock is held.
2. `sync_project "all" "$DEFAULT_DIRECTION" "all"` — pipe stdout/stderr through `log()`.
3. `release_lock`
4. `sleep $DAEMON_INTERVAL`

Traps `SIGTERM` and `SIGINT` to release the lock before exiting.

---

## Adding a new subcommand

1. Write a `cmd_<name>()` function following the existing pattern (load_config first, use `info`/`warn`/`error` for output).
2. Add a `case` entry in `main()`.
3. Add a usage line in `usage()`.
4. Document it in `docs/cli-reference.md`.
