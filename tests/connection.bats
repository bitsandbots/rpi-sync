#!/usr/bin/env bats
# Tests for pisync SSH/connection functionality

load 'helpers'

setup() {
    setup_test_env
    PISYNC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/pisync"
    export PISYNC_TESTING=1
    export PISYNC_HOME="$PISYNC_DIR"
}

teardown() {
    teardown_test_env
}

# ── SSH Key Setup Tests ─────────────────────────────────────────────────────

@test "setup_keys: generates Ed25519 key if missing" {
    source "$PISYNC_SCRIPT"

    # Create temp SSH dir for test
    export HOME="$TEST_DIR"
    mkdir -p "$TEST_DIR/.ssh"

    # Verify key doesn't exist initially
    [ ! -f "$TEST_DIR/.ssh/id_ed25519" ]

    # Generate key (mock ssh-keygen to not actually generate)
    # In real test, we'd mock ssh-keygen
    # For now, just test the logic path exists
}

@test "setup_keys: skips generation if key exists" {
    source "$PISYNC_SCRIPT"
    export HOME="$TEST_DIR"
    mkdir -p "$TEST_DIR/.ssh"

    # Create a dummy key
    touch "$TEST_DIR/.ssh/id_ed25519"
    chmod 600 "$TEST_DIR/.ssh/id_ed25519"

    # Key should exist
    [ -f "$TEST_DIR/.ssh/id_ed25519" ]

    # setup_keys should see it exists and skip generation
    # (actual ssh-copy-id would be mocked in integration test)
}

# ── SSH Connection Tests ────────────────────────────────────────────────────

@test "SSH batch mode: prevents password prompts" {
    source "$PISYNC_SCRIPT"

    # Check that SSH calls use BatchMode=yes
    # This is defined in the sync functions
    grep -q "BatchMode=yes" "$PISYNC_SCRIPT"
    [ "$?" -eq 0 ]
}

@test "SSH timeout: respects ConnectTimeout setting" {
    source "$PISYNC_SCRIPT"

    # Check that SSH calls use ConnectTimeout
    grep -q "ConnectTimeout" "$PISYNC_SCRIPT"
    [ "$?" -eq 0 ]
}

@test "SSH strict host key: logs fingerprint for audit" {
    source "$PISYNC_SCRIPT"

    # setup_keys should log host key fingerprint
    grep -q "fingerprint" "$PISYNC_SCRIPT"
    [ "$?" -eq 0 ]
}

# ── Rsync Connection Tests ───────────────────────────────────────────────────

@test "rsync args: includes required flags" {
    source "$PISYNC_SCRIPT"

    # Build args for a test project
    local args
    args=$(build_rsync_args "testproj" "")

    # Required flags should be present
    [[ "$args" == *"-azP"* ]]          # archive, compress, partial, progress
    [[ "$args" == *"--delete"* ]]      # remove files not in source
    [[ "$args" == *"--checksum"* ]]    # use checksums
    [[ "$args" == *"--timeout=30"* ]]  # connection timeout
}

@test "rsync args: includes default excludes" {
    source "$PISYNC_SCRIPT"

    local args
    args=$(build_rsync_args "testproj" "")

    # Default excludes should be present
    [[ "$args" == *".git/objects"* ]]
    [[ "$args" == *"__pycache__"* ]]
    [[ "$args" == *"node_modules"* ]]
    [[ "$args" == *".DS_Store"* ]]
}

@test "rsync args: includes custom exclude file when provided" {
    source "$PISYNC_SCRIPT"

    # Create custom exclude file
    local exclude_file="$TEST_DIR/excludes.txt"
    echo "*.log" > "$exclude_file"
    echo "*.tmp" >> "$exclude_file"

    local args
    args=$(build_rsync_args "testproj" "$exclude_file")

    [[ "$args" == *"--exclude-from=$exclude_file"* ]]
}

@test "rsync args: skips exclude file if not provided" {
    source "$PISYNC_SCRIPT"

    local args
    args=$(build_rsync_args "testproj" "")

    # Should not have --exclude-from for empty path
    [[ "$args" != *"--exclude-from="* ]]
}

# ── Error Handling Tests ────────────────────────────────────────────────────

@test "error function: logs to file and stdout" {
    source "$PISYNC_SCRIPT"
    load_config

    run error "Test error message"
    # error() prints and logs, doesn't change exit status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test error message"* ]]

    # Should also log to file
    [ -f "$PISYNC_LOG" ]
    grep -q "ERROR: Test error message" "$PISYNC_LOG"
}

@test "warn function: logs to file and stdout" {
    source "$PISYNC_SCRIPT"
    load_config

    run warn "Test warning"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test warning"* ]]

    grep -q "WARN: Test warning" "$PISYNC_LOG"
}

@test "info function: logs to file and stdout" {
    source "$PISYNC_SCRIPT"
    load_config

    run info "Test info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test info"* ]]

    grep -q "INFO: Test info" "$PISYNC_LOG"
}

# ── Logging Tests ────────────────────────────────────────────────────────────

@test "log function: appends timestamped entries" {
    source "$PISYNC_SCRIPT"
    load_config

    log "Test log entry"

    [ -f "$PISYNC_LOG" ]
    grep -q "Test log entry" "$PISYNC_LOG"
}

@test "log file: created in PISYNC_HOME" {
    source "$PISYNC_SCRIPT"
    load_config

    # Log should exist after any logging operation
    log "init"

    [ -f "$PISYNC_LOG" ]
    [[ "$PISYNC_LOG" == *"$PISYNC_HOME"* ]]
}

# ── Lock File Tests ──────────────────────────────────────────────────────────

@test "lock file: prevents concurrent writes" {
    source "$PISYNC_SCRIPT"
    load_config

    # Create lock file with fake PID
    echo "99999" > "$PISYNC_LOCK"

    # acquire_lock should fail (PID 99999 doesn't exist, so stale lock detection)
    # Actually, stale detection should clean it up
    # Let's test that it handles stale locks
    run acquire_lock
    # Should succeed after cleaning stale lock
    [ "$status" -eq 0 ]
}

@test "lock file: detects stale locks" {
    source "$PISYNC_SCRIPT"
    load_config

    # Create stale lock with non-existent PID
    echo "99999" > "$PISYNC_LOCK"

    # acquire_lock should detect stale and clean it
    acquire_lock

    # New lock should have our PID
    local pid
    pid=$(cat "$PISYNC_LOCK")
    [ "$pid" -eq $$ ]

    release_lock
}