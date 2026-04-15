#!/usr/bin/env bash
# Test helpers for pisync tests
# Source this file in bats tests: load 'helpers'

# ── Test Environment Setup ──────────────────────────────────────────────────

# Create a temporary test environment
setup_test_env() {
    export TEST_DIR
    TEST_DIR=$(mktemp -d)
    export PISYNC_DIR="$TEST_DIR/.pisync"
    export PISYNC_CONF="$PISYNC_DIR/pisync.conf"
    export PISYNC_LOG="$PISYNC_DIR/pisync.log"
    export PISYNC_STATE="$PISYNC_DIR/state"
    export PISYNC_LOCK="$PISYNC_DIR/pisync.lock"

    mkdir -p "$PISYNC_DIR" "$PISYNC_STATE"
    touch "$PISYNC_CONF" "$PISYNC_LOG"
}

# Clean up test environment
teardown_test_env() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Create a mock project directory with files
create_mock_project() {
    local name="$1"
    local path="$TEST_DIR/projects/$name"
    mkdir -p "$path"
    echo "# $name project" > "$path/README.md"
    echo "print('hello')" > "$path/main.py"
    mkdir -p "$path/subdir"
    echo "subcontent" > "$path/subdir/file.txt"
    echo "$path"
}

# Create a mock node config entry
create_mock_node() {
    local name="$1"
    local host="${2:-192.168.1.100}"
    local user="${3:-pi}"
    local port="${4:-22}"

    echo "NODE_${name}=\"${name}|${host}|${user}|${port}\"" >> "$PISYNC_CONF"
}

# Create a mock project config entry
create_mock_project_config() {
    local name="$1"
    local local_path="$2"
    local remote_path="${3:-/home/pi/projects/$name}"
    local exclude_file="${4:-}"

    echo "PROJECT_${name}=\"${name}|${local_path}|${remote_path}|${exclude_file}\"" >> "$PISYNC_CONF"
}

# ── Mock Commands ───────────────────────────────────────────────────────────

# Create mock rsync that simulates success
mock_rsync_success() {
    cat > "$TEST_DIR/mock_rsync.sh" << 'EOF'
#!/bin/bash
# Mock rsync - always succeeds
echo "sending incremental file list"
echo "sent 1,000 bytes  received 100 bytes"
exit 0
EOF
    chmod +x "$TEST_DIR/mock_rsync.sh"
    export PATH="$TEST_DIR:$PATH"
}

# Create mock rsync that simulates failure
mock_rsync_failure() {
    local error_msg="${1:-Connection refused}"
    cat > "$TEST_DIR/mock_rsync.sh" << EOF
#!/bin/bash
# Mock rsync - always fails
echo "rsync: $error_msg" >&2
exit 1
EOF
    chmod +x "$TEST_DIR/mock_rsync.sh"
    export PATH="$TEST_DIR:$PATH"
}

# Create mock SSH that simulates success
mock_ssh_success() {
    cat > "$TEST_DIR/mock_ssh.sh" << 'EOF'
#!/bin/bash
# Mock SSH - responds to specific commands
if [[ "$*" == *"hostname"* ]]; then
    echo "mock-host"
    exit 0
fi
if [[ "$*" == *"[ -f ~/.pisync/pisync.conf ]"* ]]; then
    echo "yes"
    exit 0
fi
# Default: success
exit 0
EOF
    chmod +x "$TEST_DIR/mock_ssh.sh"
    export PATH="$TEST_DIR:$PATH"
}

# Create mock SSH that simulates timeout
mock_ssh_timeout() {
    cat > "$TEST_DIR/mock_ssh.sh" << 'EOF'
#!/bin/bash
# Mock SSH - timeout
echo "ssh: connect to host: Connection timed out" >&2
exit 255
EOF
    chmod +x "$TEST_DIR/mock_ssh.sh"
    export PATH="$TEST_DIR:$PATH"
}

# Create mock SSH that simulates auth failure
mock_ssh_auth_failure() {
    cat > "$TEST_DIR/mock_ssh.sh" << 'EOF'
#!/bin/bash
# Mock SSH - permission denied
echo "pi@host: Permission denied (publickey)" >&2
exit 255
EOF
    chmod +x "$TEST_DIR/mock_ssh.sh"
    export PATH="$TEST_DIR:$PATH"
}

# Create mock avahi-browse
mock_avahi_browse() {
    cat > "$TEST_DIR/mock_avahi-browse.sh" << 'EOF'
#!/bin/bash
# Mock avahi-browse output
if [[ "$*" == *"-t"* && "$*" == *"_pisync._tcp"* ]]; then
    echo "=; _pisync._tcp; local; hostname = [mock-pi-1.local]"
    echo "=; _pisync._tcp; local; hostname = [mock-pi-2.local]"
fi
exit 0
EOF
    chmod +x "$TEST_DIR/mock_avahi-browse.sh"
    export PATH="$TEST_DIR:$PATH"
}

# Mock TCP connection (for bash /dev/tcp)
# This requires creating a mock bash that intercepts /dev/tcp
# For simplicity, tests should use mocked SSH instead

# ── Assertion Helpers ──────────────────────────────────────────────────────

# Assert that output contains expected string
# Note: 'output' is provided by bats run command
# shellcheck disable=SC2154
assert_output_contains() {
    local expected="$1"
    [[ "$output" == *"$expected"* ]]
}

# Assert that output does NOT contain string
assert_output_not_contains() {
    local unexpected="$1"
    [[ "$output" != *"$unexpected"* ]]
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    [ -f "$file" ]
}

# Assert directory exists
assert_dir_exists() {
    local dir="$1"
    [ -d "$dir" ]
}

# Assert state file was created
assert_state_file_exists() {
    local project="$1"
    local host="$2"
    [ -f "$PISYNC_STATE/${project}_${host}.last" ]
}

# ── Run pisync command in test environment ────────────────────────────────

# Source pisync for testing (sets PISYNC_TESTING to prevent main() execution)
source_pisync() {
    export PISYNC_TESTING=1
    export PISYNC_HOME="$PISYNC_DIR"
    export PISYNC_CONF PISYNC_LOG PISYNC_LOCK PISYNC_STATE
    # shellcheck source=/dev/null
    source "$PISYNC_SCRIPT"
}

run_pisync() {
    # Source pisync with test environment
    export PISYNC_TESTING=1
    export PISYNC_HOME="$PISYNC_DIR"
    export PISYNC_DIR PISYNC_CONF PISYNC_LOG PISYNC_STATE PISYNC_LOCK
    cd "$TEST_DIR" || return 1
    bash -c "PISYNC_TESTING=1 PISYNC_HOME='$PISYNC_DIR' source '$PISYNC_SCRIPT' && $*" 2>&1
}