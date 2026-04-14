#!/usr/bin/env bash
# ============================================================================
# PiSync Installer
# CoreConduit Consulting Services | MIT License
# ============================================================================
# Installs PiSync and all required dependencies on a Raspberry Pi (or any
# Debian/Ubuntu system). Run on EACH node in your Pi network.
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
PISYNC_SRC="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}  ${BOLD}Pi${ORANGE}Sync${NC} ${DIM}Installer${NC}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${DIM}CoreConduit Consulting Services${NC}              ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Pre-flight checks ──────────────────────────────────────────────────────
if [ "$(id -u)" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Running as root. PiSync will be configured for: ${SUDO_USER:-root}"
    TARGET_USER="${SUDO_USER:-root}"
else
    TARGET_USER="$USER"
fi

# ── Dependencies ───────────────────────────────────────────────────────────
echo -e "  ${BLUE}→${NC} Checking dependencies..."

DEPS_MISSING=()

check_dep() {
    if ! command -v "$1" &>/dev/null; then
        DEPS_MISSING+=("$2")
    else
        echo -e "  ${GREEN}✓${NC} $1"
    fi
}

check_dep rsync rsync
check_dep ssh openssh-client
check_dep sshd openssh-server
check_dep avahi-browse avahi-utils
check_dep inotifywait inotify-tools

if [ ${#DEPS_MISSING[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${BLUE}→${NC} Installing missing packages: ${DEPS_MISSING[*]}..."
    if [ "$(id -u)" -eq 0 ]; then
        apt-get update -qq
        apt-get install -y -qq "${DEPS_MISSING[@]}"
    else
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${DEPS_MISSING[@]}"
    fi
    echo -e "  ${GREEN}✓${NC} Dependencies installed"
fi

# ── Enable SSH Server ──────────────────────────────────────────────────────
if ! systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "  ${BLUE}→${NC} Enabling SSH server..."
    if [ "$(id -u)" -eq 0 ]; then
        systemctl enable ssh
        systemctl start ssh
    else
        sudo systemctl enable ssh
        sudo systemctl start ssh
    fi
    echo -e "  ${GREEN}✓${NC} SSH server enabled"
fi

# ── Enable Avahi ───────────────────────────────────────────────────────────
if ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    echo -e "  ${BLUE}→${NC} Enabling Avahi mDNS..."
    if [ "$(id -u)" -eq 0 ]; then
        systemctl enable avahi-daemon
        systemctl start avahi-daemon
    else
        sudo systemctl enable avahi-daemon
        sudo systemctl start avahi-daemon
    fi
    echo -e "  ${GREEN}✓${NC} Avahi mDNS enabled"
fi

# ── Install PiSync ─────────────────────────────────────────────────────────
echo -e "  ${BLUE}→${NC} Installing pisync to ${INSTALL_DIR}..."

if [ "$(id -u)" -eq 0 ]; then
    cp "$PISYNC_SRC/pisync" "$INSTALL_DIR/pisync"
    chmod +x "$INSTALL_DIR/pisync"
else
    sudo cp "$PISYNC_SRC/pisync" "$INSTALL_DIR/pisync"
    sudo chmod +x "$INSTALL_DIR/pisync"
fi

echo -e "  ${GREEN}✓${NC} pisync installed to ${INSTALL_DIR}/pisync"

# ── Verify ─────────────────────────────────────────────────────────────────
echo ""
if command -v pisync &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Installation verified: $(pisync --version)"
else
    echo -e "  ${YELLOW}⚠${NC} pisync not found in PATH. You may need to add ${INSTALL_DIR} to your PATH."
fi

# ── Next Steps ─────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Installation complete!${NC}"
echo ""
echo -e "  ${BOLD}Quick start:${NC}"
echo -e "    ${CYAN}pisync init${NC}                  Set up this node"
echo -e "    ${CYAN}pisync add-node pi2 10.0.0.2${NC} Register a peer"
echo -e "    ${CYAN}pisync keys 10.0.0.2${NC}         Deploy SSH keys"
echo -e "    ${CYAN}pisync sync${NC}                  Sync all projects"
echo -e "    ${CYAN}pisync install-service${NC}        Enable auto-sync daemon"
echo ""
echo -e "  ${DIM}Run this installer on each node in your Pi network.${NC}"
echo ""
