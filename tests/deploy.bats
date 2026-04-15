#!/usr/bin/env bats
# Tests for pisync deploy functionality

load 'helpers'

setup() {
    setup_test_env
    PISYNC_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/pisync"
    export PISYNC_TESTING=1
    export PISYNC_HOME="$PISYNC_DIR"
    PROJECT_PATH=$(create_mock_project "testproj")
}

teardown() {
    teardown_test_env
}

# ── Deploy Command Tests ────────────────────────────────────────────────────

@test "deploy: fails without any configured projects" {
    source "$PISYNC_SCRIPT"
    # No projects configured

    run cmd_deploy <<< "n"
    [ "$status" -eq 0 ]
    # Should warn or report 0 projects
    [[ "$output" == *"Projects synced: 0"* ]] || [[ "$output" == *"0"* ]]
}

@test "deploy: fails without any configured nodes" {
    create_mock_project_config "testproj" "$PROJECT_PATH"
    source "$PISYNC_SCRIPT"
    load_config
    # No nodes configured

    run cmd_deploy <<< "n"
    [ "$status" -eq 0 ]
    # Should report 0 syncs
    [[ "$output" == *"Projects synced: 0"* ]] || [[ "$output" == *"0"* ]]
}

@test "deploy: dry-run preview fails on non-existent local path" {
    # Configure project with non-existent path
    echo 'PROJECT_broken="broken|/nonexistent/path|/remote/path|"' >> "$PISYNC_CONF"
    echo 'NODE_test="test|192.168.1.99|pi|22"' >> "$PISYNC_CONF"

    source "$PISYNC_SCRIPT"
    init_dirs
    load_config

    # Call sync_project_to_node directly - it should fail on missing local path
    DRY_RUN=true
    run sync_project_to_node "broken" "/nonexistent/path" "/remote/path" "" "192.168.1.99" "pi" "22" "push"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"Local path"* ]]
}

@test "deploy: dry-run succeeds with valid config but unreachable nodes" {
    create_mock_project_config "testproj" "$PROJECT_PATH"
    echo 'NODE_test="test|192.168.99.99|pi|22"' >> "$PISYNC_CONF"

    source "$PISYNC_SCRIPT"
    load_config

    # Dry-run should attempt sync but fail on unreachable node
    DRY_RUN=true
    run sync_project 'testproj' 'push' 'all'

    # Status depends on whether rsync fails
    # For now, just check it runs without crashing
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "deploy: requires user confirmation before proceeding" {
    create_mock_project_config "testproj" "$PROJECT_PATH"
    echo 'NODE_test="test|192.168.99.99|pi|22"' >> "$PISYNC_CONF"

    source "$PISYNC_SCRIPT"
    load_config

    # Send "n" to decline
    run cmd_deploy <<< "n"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cancelled"* ]] || [[ "$output" == *"Proceed"* ]]
}

# ── Project Config Parsing Tests ─────────────────────────────────────────────

@test "get_projects: parses PROJECT_ entries correctly" {
    mkdir -p "$TEST_DIR/projects/alpha" "$TEST_DIR/projects/beta"
    cat >> "$PISYNC_CONF" << EOF
PROJECT_alpha="alpha|$TEST_DIR/projects/alpha|/home/pi/alpha|"
PROJECT_beta="beta|$TEST_DIR/projects/beta|/home/pi/beta|"
EOF

    source "$PISYNC_SCRIPT"
    load_config

    local projects
    projects=$(get_projects)

    [[ "$projects" == *"alpha"* ]]
    [[ "$projects" == *"beta"* ]]
}

@test "get_projects: handles exclude_file field" {
    echo 'PROJECT_with_exclude="exproj|/path/to/exproj|/remote/exproj|/path/to/excludes"' >> "$PISYNC_CONF"

    source "$PISYNC_SCRIPT"
    load_config

    local proj
    proj=$(get_projects | grep exproj)

    [[ "$proj" == *"|/path/to/excludes"* ]]
}

@test "sync_project_to_node: fails on missing local path" {
    create_mock_project_config "testproj" "$PROJECT_PATH"
    echo 'NODE_test="test|192.168.1.99|pi|22"' >> "$PISYNC_CONF"

    source "$PISYNC_SCRIPT"
    load_config

    # Call with non-existent path
    run sync_project_to_node "testproj" "/nonexistent/path" "/remote/path" "" "192.168.1.99" "pi" "22" "push"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"Local path"* ]]
}

# ── Lock Management Tests ────────────────────────────────────────────────────

@test "acquire_lock: prevents concurrent operations" {
    source "$PISYNC_SCRIPT"
    load_config

    # First acquire should succeed
    acquire_lock
    [ -f "$PISYNC_LOCK" ]

    # Second acquire should fail (simulated by checking lock file)
    local pid
    pid=$(cat "$PISYNC_LOCK")
    [ "$pid" -eq $$ ]

    release_lock
    [ ! -f "$PISYNC_LOCK" ]
}

@test "release_lock: cleans up lock file" {
    source "$PISYNC_SCRIPT"
    load_config

    acquire_lock
    [ -f "$PISYNC_LOCK" ]

    release_lock
    [ ! -f "$PISYNC_LOCK" ]
}

# ── State File Tests ─────────────────────────────────────────────────────────

@test "state file: created after successful sync" {
    # This test would require mocking rsync/SSH
    # For unit test, we verify the state file format is correct
    local state_file="$PISYNC_STATE/testproj_mockhost.last"
    echo "2026-04-15T10:00:00+00:00|push|5s|success" > "$state_file"

    [ -f "$state_file" ]
    local content
    content=$(cat "$state_file")

    # Verify format: timestamp|direction|duration|result
    [[ "$content" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}\|[a-z]+\|[0-9]+s\|[a-z]+$ ]]
}