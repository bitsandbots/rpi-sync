#!/usr/bin/env bash
# ============================================================================
# rpi-sync Health Check
# Verifies installation, connectivity, and configuration on this node.
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

RPI_SYNC_HOME="${RPI_SYNC_HOME:-$HOME/.rpi-sync}"
RPI_SYNC_CONF="$RPI_SYNC_HOME/rpi-sync.conf"
PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    shift
    if "$@" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${desc}"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} ${desc}"
        ((FAIL++))
    fi
}

check_warn() {
    local desc="$1"
    shift
    if "$@" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${desc}"
        ((PASS++))
    else
        echo -e "  ${YELLOW}⚠${NC} ${desc}"
        ((WARN++))
    fi
}

echo ""
echo -e "  ${BOLD}rpi-sync Health Check${NC}"
echo -e "  ${DIM}───────────────────────────────────────${NC}"
echo ""

# ── System ─────────────────────────────────────────────────────────────────
echo -e "  ${BOLD}System${NC}"
check "rsync installed" command -v rsync
check "ssh client installed" command -v ssh
check "sshd running" systemctl is-active ssh
check_warn "avahi-daemon running" systemctl is-active avahi-daemon
check_warn "inotifywait installed" command -v inotifywait
check "SSH key exists" test -f "$HOME/.ssh/id_ed25519" -o -f "$HOME/.ssh/id_rsa"
echo ""

# ── Configuration ──────────────────────────────────────────────────────────
echo -e "  ${BOLD}Configuration${NC}"
check "rpi-sync home exists" test -d "$RPI_SYNC_HOME"
check "Config file exists" test -f "$RPI_SYNC_CONF"

if [ -f "$RPI_SYNC_CONF" ]; then
    check "At least one project defined" grep -q '^PROJECT_' "$RPI_SYNC_CONF"
    check "At least one node defined" grep -q '^NODE_' "$RPI_SYNC_CONF"

    # Check project paths exist
    grep '^PROJECT_' "$RPI_SYNC_CONF" 2>/dev/null | while IFS='=' read -r key value; do
        local clean="${value//\"/}"
        local name path
        IFS='|' read -r name path _ _ <<< "$clean"
        check "Project path exists: ${name}" test -d "$path"
    done
fi
echo ""

# ── Network ────────────────────────────────────────────────────────────────
echo -e "  ${BOLD}Network${NC}"
local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
echo -e "  ${DIM}  This node: $(hostname) (${local_ip})${NC}"

if [ -f "$RPI_SYNC_CONF" ]; then
    # shellcheck source=/dev/null
    source "$RPI_SYNC_CONF"

    grep '^NODE_' "$RPI_SYNC_CONF" 2>/dev/null | while IFS='=' read -r key value; do
        local clean="${value//\"/}"
        local name host user port
        IFS='|' read -r name host user port <<< "$clean"
        [ -z "$host" ] && continue
        local p="${port:-22}"

        if timeout 2 bash -c "echo >/dev/tcp/$host/$p" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Node reachable: ${name} (${host}:${p})"
            ((PASS++))

            # Test SSH auth
            if ssh -p "$p" -o ConnectTimeout=3 -o BatchMode=yes \
                "${user:-$SYNC_USER}@${host}" "echo ok" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} SSH auth works: ${name}"
                ((PASS++))
            else
                echo -e "  ${YELLOW}⚠${NC} SSH auth needs setup: rpi-sync keys ${host}"
                ((WARN++))
            fi
        else
            echo -e "  ${RED}✗${NC} Node unreachable: ${name} (${host}:${p})"
            ((FAIL++))
        fi
    done
fi
echo ""

# ── Service ────────────────────────────────────────────────────────────────
echo -e "  ${BOLD}Service${NC}"
check_warn "rpi-sync daemon installed" systemctl is-enabled rpi-sync 2>/dev/null
check_warn "rpi-sync daemon running" systemctl is-active rpi-sync 2>/dev/null
check_warn "Avahi rpi-sync service registered" test -f /etc/avahi/services/rpi-sync.service
echo ""

# ── Summary ────────────────────────────────────────────────────────────────
echo -e "  ${DIM}───────────────────────────────────────${NC}"
echo -e "  ${GREEN}✓ ${PASS} passed${NC}  ${YELLOW}⚠ ${WARN} warnings${NC}  ${RED}✗ ${FAIL} failed${NC}"

if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Some checks failed. Review above for details.${NC}"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "  ${YELLOW}Optional features not configured. See docs for setup.${NC}"
fi
echo ""
