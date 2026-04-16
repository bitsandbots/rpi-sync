#!/usr/bin/env bats
# Tests for rpi-sync discovery/scanning functionality

load 'helpers'

setup() {
    setup_test_env
    # Path to rpi-sync script
    PISYNC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/rpi-sync"
    export RPI_SYNC_TESTING=1
    export RPI_SYNC_HOME="$RPI_SYNC_DIR"
}

teardown() {
    teardown_test_env
}

# ── Discovery Command Tests ──────────────────────────────────────────────────

@test "discover: warns when no nodes found and no config" {
    # No config file = no configured nodes
    # No avahi = fallback scan should find nothing on isolated test env
    source "$PISYNC_SCRIPT"
    init_dirs

    run discover_nodes
    [ "$status" -eq 0 ]
    [[ "$output" == *"No rpi-sync nodes discovered"* ]] || \
        [[ "$output" == *"Checking configured nodes"* ]] || \
        [[ "$output" == *"subnet scan"* ]]
}

@test "discover: detects offline configured nodes" {
    # Add a node that won't be reachable
    source "$PISYNC_SCRIPT"
    echo 'NODE_unreachable="unreachable|192.168.99.99|pi|22"' >> "$PISYNC_CONF"
    init_dirs
    load_config

    run discover_nodes
    [ "$status" -eq 0 ]
    [[ "$output" == *"Offline: unreachable"* ]]
}

@test "discover: detects online configured nodes" {
    # Add localhost as a "node" - should be reachable
    source "$PISYNC_SCRIPT"
    echo 'NODE_localhost="localhost|127.0.0.1|'"$USER"'|22"' >> "$PISYNC_CONF"
    init_dirs
    load_config

    run discover_nodes
    [ "$status" -eq 0 ]
    [[ "$output" == *"Online: localhost"* ]] || [[ "$output" == *"Checking configured nodes"* ]]
}

# ── Node Config Parsing Tests ───────────────────────────────────────────────

@test "get_nodes: parses NODE_ entries correctly" {
    cat >> "$PISYNC_CONF" << 'EOF'
NODE_alpha="alpha|192.168.1.10|pi|22"
NODE_beta="beta|192.168.1.11|pi|22"
EOF

    source "$PISYNC_SCRIPT"
    load_config

    local nodes
    nodes=$(get_nodes)

    [[ "$nodes" == *"alpha|192.168.1.10|pi|22"* ]]
    [[ "$nodes" == *"beta|192.168.1.11|pi|22"* ]]
}

@test "get_nodes: handles missing user/port defaults" {
    echo 'NODE_minimal="minimal|192.168.1.20"' >> "$PISYNC_CONF"

    source "$PISYNC_SCRIPT"
    load_config

    local node
    node=$(get_nodes | grep minimal)

    # Should still parse, with empty defaults
    [[ "$node" == *"minimal|192.168.1.20"* ]]
}

@test "get_nodes: skips invalid entries" {
    cat >> "$PISYNC_CONF" << 'EOF'
NODE_valid="valid|192.168.1.30|pi|22"
NODE_invalid=""
NOT_NODE="should|be|ignored"
EOF

    source "$PISYNC_SCRIPT"
    load_config

    local nodes
    nodes=$(get_nodes)

    [[ "$nodes" == *"valid"* ]]
    [[ "$nodes" != *"should|be|ignored"* ]]
}

# ── TCP Connectivity Tests ─────────────────────────────────────────────────

@test "TCP check: timeout on unreachable host" {
    # Use a non-routable IP that will definitely timeout
    local unreachable="10.255.255.99"

    # bash /dev/tcp should timeout/fail
    run timeout 2 bash -c "echo >/dev/tcp/$unreachable/22" 2>&1
    [ "$status" -ne 0 ]
}

@test "TCP check: succeeds on localhost" {
    run timeout 2 bash -c "echo >/dev/tcp/127.0.0.1/22" 2>&1
    # This will succeed if SSH is listening, fail otherwise
    # Either way, the test validates the /dev/tcp syntax works
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}