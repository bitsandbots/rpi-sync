#!/usr/bin/env bash
# ============================================================================
# PiSync SSH Key Setup
# CoreConduit Consulting Services | MIT License
# ============================================================================
# Automates SSH key distribution across all configured Pi nodes.
# Uses password authentication once per node to bootstrap key-based auth.
#
# Usage:
#   ./setup-ssh-keys.sh              # Copy keys to all nodes
#   ./setup-ssh-keys.sh --check      # Verify SSH access only
#   ./setup-ssh-keys.sh --node pi2   # Setup specific node only
#   ./setup-ssh-keys.sh --generate   # Generate new key if missing
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
NC='\033[0m'

PISYNC_CONF="${PISYNC_CONF:-$HOME/.pisync/pisync.conf}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_KEY_PUB="${SSH_KEY}.pub"
SPECIFIC_NODE=""
CHECK_ONLY=false
GENERATE_KEY=false
SKIP_SSH_CONFIG=false

# ── Parse arguments ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)
            CHECK_ONLY=true
            shift
            ;;
        --node|-n)
            SPECIFIC_NODE="${2:?--node requires a node name}"
            shift 2
            ;;
        --generate|-g)
            GENERATE_KEY=true
            shift
            ;;
        --skip-config|-s)
            SKIP_SSH_CONFIG=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--check] [--node NAME] [--generate] [--skip-config]"
            echo "  --check       Verify SSH access to all nodes"
            echo "  --node NAME   Setup specific node only"
            echo "  --generate    Generate new SSH key if missing"
            echo "  --skip-config Skip SSH config auto-configuration"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ── Banner ────────────────────────────────────────────────────────────────
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}Pi${ORANGE}Sync${NC} ${DIM}SSH Key Setup${NC}                         ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${DIM}CoreConduit Consulting Services${NC}              ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── No sshpass needed — SSH prompts natively via /dev/tty ─────────────────

# ── Check for SSH key ────────────────────────────────────────────────────
if [ ! -f "$SSH_KEY_PUB" ]; then
    if [ "$GENERATE_KEY" = true ]; then
        echo -e "  ${BLUE}→${NC} Generating new SSH key (${SSH_KEY})..."
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "$USER@$(hostname)"
        echo -e "  ${GREEN}✓${NC} SSH key generated"
    else
        echo -e "  ${RED}✗${NC} No SSH key found at ${SSH_KEY_PUB}"
        echo ""
        echo "  Generate one with:"
        echo -e "    ${DIM}ssh-keygen -t ed25519 -f ${SSH_KEY}${NC}"
        echo ""
        echo "  Or run with --generate to create one automatically"
        exit 1
    fi
else
    KEY_FP=$(ssh-keygen -lf "$SSH_KEY_PUB" 2>/dev/null | awk '{print $2}')
    KEY_COMMENT=$(ssh-keygen -lf "$SSH_KEY_PUB" 2>/dev/null | awk '{print $NF}')
    echo -e "  ${GREEN}✓${NC} SSH key: ${DIM}${SSH_KEY_PUB}${NC}"
    echo -e "    Fingerprint: ${KEY_FP}"
    echo -e "    Comment: ${KEY_COMMENT}"
fi

# ── Check for config file ────────────────────────────────────────────────
if [ ! -f "$PISYNC_CONF" ]; then
    echo -e "  ${RED}✗${NC} Config not found: ${PISYNC_CONF}"
    echo ""
    echo "  Run 'pisync init' first to create a configuration"
    exit 1
fi

# ── Extract SYNC_USER from config ────────────────────────────────────────
SYNC_USER=$(grep '^SYNC_USER=' "$PISYNC_CONF" 2>/dev/null | cut -d'"' -f2 || echo "$USER")
echo -e "  ${DIM}Sync user: ${SYNC_USER}${NC}"
echo ""

# ── Parse nodes from config ──────────────────────────────────────────────
declare -A NODES

parse_nodes() {
    local line name host user port
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Parse NODE_NN="name|host|user|port"
        if [[ "$line" =~ ^NODE_[0-9]+= ]]; then
            local value
            value=$(echo "$line" | cut -d'"' -f2)
            name=$(echo "$value" | cut -d'|' -f1)
            host=$(echo "$value" | cut -d'|' -f2)
            user=$(echo "$value" | cut -d'|' -f3)
            port=$(echo "$value" | cut -d'|' -f4)

            # Use SYNC_USER if user field is empty
            user="${user:-$SYNC_USER}"
            port="${port:-22}"

            if [ -n "$SPECIFIC_NODE" ] && [ "$name" != "$SPECIFIC_NODE" ]; then
                continue
            fi

            NODES["$name"]="${user}|${host}|${port}"
        fi
    done < "$PISYNC_CONF"
}

parse_nodes

if [ ${#NODES[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} No nodes configured"
    echo ""
    echo "  Add nodes with:"
    echo -e "    ${DIM}pisync add-node <name> <host> [user] [port]${NC}"
    exit 0
fi

echo -e "  ${BOLD}Nodes to setup:${NC}"
for name in "${!NODES[@]}"; do
    IFS='|' read -r user host port <<< "${NODES[$name]}"
    echo -e "    ${CYAN}${name}${NC} → ${user}@${host}:${port}"
done
echo ""

# ── Check only mode ──────────────────────────────────────────────────────
if [ "$CHECK_ONLY" = true ]; then
    echo -e "  ${BLUE}→${NC} Verifying SSH access..."
    echo ""
    FAILED=0
    for name in "${!NODES[@]}"; do
        IFS='|' read -r user host port <<< "${NODES[$name]}"
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "${user}@${host}" "hostname" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} ${name} (${user}@${host})"
        else
            echo -e "  ${RED}✗${NC} ${name} (${user}@${host}) — SSH failed"
            ((FAILED++))
        fi
    done
    echo ""
    if [ $FAILED -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} All ${#NODES[@]} nodes accessible"
        exit 0
    else
        echo -e "  ${RED}✗${NC} ${FAILED}/${#NODES[@]} nodes failed"
        exit 1
    fi
fi

# ── Update SSH config for pisync nodes ──────────────────────────────────────
update_ssh_config() {
    local ssh_config="$HOME/.ssh/config"
    local marker="# --- PiSync nodes (auto-generated) ---"
    local hosts=""

    # Build host list
    for name in "${!NODES[@]}"; do
        IFS='|' read -r user host port <<< "${NODES[$name]}"
        hosts="$hosts $host"
    done
    hosts=$(echo "$hosts" | xargs)  # Trim leading space

    if [ -z "$hosts" ]; then
        return 0
    fi

    # Check if we need to update
    if grep -q "$marker" "$ssh_config" 2>/dev/null; then
        # Update existing block
        local temp_file
        temp_file=$(mktemp)
        awk -v marker="$marker" -v hosts="$hosts" -v keyfile="$SSH_KEY" '
            $0 ~ marker {
                print marker
                print "Host " hosts
                print "    IdentityFile " keyfile
                print "    IdentitiesOnly yes"
                print "    BatchMode yes"
                print "# --- End PiSync ---"
                skip = 1
                next
            }
            skip && /^# --- End PiSync/ { skip = 0; next }
            skip { next }
            { print }
        ' "$ssh_config" > "$temp_file"
        mv "$temp_file" "$ssh_config"
        chmod 600 "$ssh_config"
        echo -e "  ${GREEN}✓${NC} Updated SSH config for pisync nodes"
    else
        # Append new block
        {
            echo ""
            echo "$marker"
            echo "Host $hosts"
            echo "    IdentityFile $SSH_KEY"
            echo "    IdentitiesOnly yes"
            echo "    BatchMode yes"
            echo "# --- End PiSync ---"
        } >> "$ssh_config"
        chmod 600 "$ssh_config"
        echo -e "  ${GREEN}✓${NC} Added SSH config for pisync nodes"
    fi
}

# ── Check for interactive terminal ──────────────────────────────────────────
if [ ! -t 0 ]; then
    echo -e "  ${RED}✗${NC} This script requires an interactive terminal for password input."
    echo ""
    echo "  Run directly from a terminal:"
    echo -e "    ${DIM}./setup-ssh-keys.sh${NC}"
    echo ""
    echo "  Or use --check to verify SSH access only:"
    echo -e "    ${DIM}./setup-ssh-keys.sh --check${NC}"
    exit 1
fi

# ── Prompt for password ──────────────────────────────────────────────────────
echo -e "  ${BOLD}Enter password for each node when prompted.${NC}"
echo -e "  ${DIM}(Password for '${SYNC_USER}' on each remote node)${NC}"
echo ""

# ── Copy keys to each node ───────────────────────────────────────────────
SUCCESS=0
FAILED=0
FAILED_NODES=()

for name in "${!NODES[@]}"; do
    IFS='|' read -r user host port <<< "${NODES[$name]}"

    echo -e "  ${BLUE}→${NC} Copying key to ${name} (${user}@${host})..."

    # Check if SSH already works (key already present)
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "${user}@${host}" "exit 0" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} SSH already configured for ${name}"
        ((SUCCESS++))
        continue
    fi

    # Pre-add host key to known_hosts so SSH won't ask yes/no interactively.
    # SSH then prompts for the password natively via /dev/tty — no sshpass needed.
    echo -e "  ${DIM}Fetching host key for ${host}...${NC}"
    ssh-keyscan -T 5 -p "$port" -H "$host" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

    echo -e "  ${DIM}Enter password for ${user}@${host} when SSH prompts below:${NC}"
    if ssh -p "$port" \
            -o ConnectTimeout=10 \
            -o PasswordAuthentication=yes \
            -o PubkeyAuthentication=no \
            "${user}@${host}" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
            < "$SSH_KEY_PUB"; then
        echo -e "  ${GREEN}✓${NC} Key copied to ${name}"
        ((SUCCESS++))
    else
        echo -e "  ${RED}✗${NC} Failed to copy key to ${name} — wrong password or SSH not reachable"
        ((FAILED++))
        FAILED_NODES+=("$name")
    fi
done

echo ""
echo -e "  ${BOLD}Summary:${NC} ${GREEN}${SUCCESS} succeeded${NC}, ${RED}${FAILED} failed${NC}"

# ── Verify access ─────────────────────────────────────────────────────────
if [ $SUCCESS -gt 0 ]; then
    echo ""
    echo -e "  ${BLUE}→${NC} Verifying SSH access..."

    for name in "${!NODES[@]}"; do
        if [[ " ${FAILED_NODES[*]} " =~ \ ${name}\  ]]; then
            continue
        fi

        IFS='|' read -r user host port <<< "${NODES[$name]}"

        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "${user}@${host}" "hostname" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} ${name} — SSH working"
        else
            echo -e "  ${YELLOW}⚠${NC} ${name} — Key copied but SSH still fails (check authorized_keys format)"
        fi
    done
fi

echo ""

if [ $FAILED -gt 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Some nodes failed. Check:"
    echo -e "    - Password was correct for '${SYNC_USER}'"
    echo -e "    - SSH server is running on failed nodes"
    echo -e "    - Network connectivity to failed nodes"
    exit 1
fi

# ── Update SSH config ───────────────────────────────────────────────────────
if [ "$SKIP_SSH_CONFIG" = false ] && [ $SUCCESS -gt 0 ]; then
    echo ""
    echo -e "  ${BLUE}→${NC} Configuring SSH config for BatchMode..."
    update_ssh_config
fi

echo -e "  ${GREEN}✓${NC} All nodes configured for key-based SSH access"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo -e "    ${DIM}pisync status${NC}    Check node connectivity"
echo -e "    ${DIM}pisync deploy${NC}    Sync projects to all nodes"
echo ""