#!/usr/bin/env bash
# ============================================================================
# PiSync Installer
# CoreConduit Consulting Services | MIT License
# ============================================================================
# Installs PiSync and all required dependencies on a Raspberry Pi (or any
# Debian/Ubuntu system). Run on EACH node in your Pi network.
#
# Usage:
#   sudo ./install.sh              Install to /usr/local/bin (default)
#   ./install.sh --prefix ~/.local Install without sudo (user-local)
#   ./install.sh --check           Verify dependencies only, don't install
#   ./install.sh --uninstall       Remove PiSync binary
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

PISYNC_SRC="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CHECK_ONLY=false
UNINSTALL=false

# ── Parse arguments ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            INSTALL_DIR="${2:?--prefix requires a path}/bin"
            shift 2
            ;;
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--prefix PATH] [--check] [--uninstall]"
            echo "  --prefix PATH   Install to PATH/bin instead of /usr/local/bin"
            echo "  --check         Verify dependencies only"
            echo "  --uninstall     Remove pisync binary"
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
echo -e "${BLUE}║${NC}  ${BOLD}Pi${ORANGE}Sync${NC} ${DIM}Installer${NC}                              ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${DIM}CoreConduit Consulting Services${NC}              ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Detect version in source ──────────────────────────────────────────────
SRC_VERSION=$(grep '^PISYNC_VERSION=' "$PISYNC_SRC/pisync" | head -1 | cut -d'"' -f2)
echo -e "  ${DIM}Source version: ${SRC_VERSION}${NC}"

# ── Uninstall mode ────────────────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    TARGET="${INSTALL_DIR}/pisync"
    if [ -f "$TARGET" ]; then
        if [ "$(id -u)" -eq 0 ] || [ -w "$INSTALL_DIR" ]; then
            rm -f "$TARGET"
        else
            sudo rm -f "$TARGET"
        fi
        echo -e "  ${GREEN}✓${NC} Removed ${TARGET}"
    else
        echo -e "  ${YELLOW}⚠${NC} pisync not found at ${TARGET}"
    fi
    echo -e "  ${DIM}Config and state in ~/.pisync/ were not removed.${NC}"
    echo -e "  ${DIM}To fully remove: rm -rf ~/.pisync/${NC}"
    exit 0
fi

# ── Determine privilege model ─────────────────────────────────────────────
USE_SUDO=false
if [ "$(id -u)" -eq 0 ]; then
    TARGET_USER="${SUDO_USER:-root}"
    echo -e "  ${YELLOW}⚠${NC} Running as root. Installing for: ${TARGET_USER}"
elif [ -w "$INSTALL_DIR" ]; then
    TARGET_USER="$USER"
else
    USE_SUDO=true
    TARGET_USER="$USER"
fi

run_privileged() {
    if [ "$USE_SUDO" = true ]; then
        sudo "$@"
    else
        "$@"
    fi
}

# ── Check for existing installation ──────────────────────────────────────
EXISTING_VERSION=""
if command -v pisync &>/dev/null; then
    EXISTING_VERSION=$(pisync --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    if [ -n "$EXISTING_VERSION" ]; then
        echo -e "  ${YELLOW}⚠${NC} PiSync ${EXISTING_VERSION} already installed — upgrading to ${SRC_VERSION}"
    fi
fi

# ── Check dependencies ────────────────────────────────────────────────────
echo ""
echo -e "  ${BLUE}→${NC} Checking dependencies..."

DEPS_MISSING=()

check_dep() {
    local cmd="$1" pkg="$2" required="${3:-required}"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${cmd}"
    elif [ "$required" = "optional" ]; then
        echo -e "  ${YELLOW}⚠${NC} ${cmd} (optional — ${pkg})"
    else
        echo -e "  ${RED}✗${NC} ${cmd} (missing — will install ${pkg})"
        DEPS_MISSING+=("$pkg")
    fi
}

check_dep rsync         rsync
check_dep ssh           openssh-client
check_dep sshd          openssh-server
check_dep avahi-browse  avahi-utils  optional
check_dep inotifywait   inotify-tools optional

if [ "$CHECK_ONLY" = true ]; then
    echo ""
    if [ ${#DEPS_MISSING[@]} -gt 0 ]; then
        echo -e "  ${RED}✗${NC} Missing required packages: ${DEPS_MISSING[*]}"
        echo -e "  ${DIM}Install with: sudo apt install ${DEPS_MISSING[*]}${NC}"
        exit 1
    else
        echo -e "  ${GREEN}✓${NC} All required dependencies present"
        exit 0
    fi
fi

# ── Install missing dependencies ──────────────────────────────────────────
if [ ${#DEPS_MISSING[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${BLUE}→${NC} Installing: ${DEPS_MISSING[*]}..."
    run_privileged apt-get update -qq
    run_privileged apt-get install -y -qq "${DEPS_MISSING[@]}"
    echo -e "  ${GREEN}✓${NC} Dependencies installed"
fi

# ── Enable SSH server ─────────────────────────────────────────────────────
if ! systemctl is-active --quiet ssh 2>/dev/null; then
    echo -e "  ${BLUE}→${NC} Enabling SSH server..."
    run_privileged systemctl enable ssh
    run_privileged systemctl start ssh
    echo -e "  ${GREEN}✓${NC} SSH server enabled"
fi

# ── Enable Avahi ──────────────────────────────────────────────────────────
if command -v avahi-daemon &>/dev/null && ! systemctl is-active --quiet avahi-daemon 2>/dev/null; then
    echo -e "  ${BLUE}→${NC} Enabling Avahi mDNS..."
    run_privileged systemctl enable avahi-daemon
    run_privileged systemctl start avahi-daemon
    echo -e "  ${GREEN}✓${NC} Avahi mDNS enabled"
fi

# ── Install PiSync binary ─────────────────────────────────────────────────
echo ""
echo -e "  ${BLUE}→${NC} Installing pisync → ${INSTALL_DIR}/pisync..."

# Create install dir if it doesn't exist (common for --prefix ~/.local/bin)
if [ ! -d "$INSTALL_DIR" ]; then
    run_privileged mkdir -p "$INSTALL_DIR"
fi

run_privileged cp "$PISYNC_SRC/pisync" "$INSTALL_DIR/pisync"
run_privileged chmod +x "$INSTALL_DIR/pisync"
echo -e "  ${GREEN}✓${NC} pisync installed"

# ── Install exclude templates ─────────────────────────────────────────────
SHARE_DIR="/usr/local/share/pisync"
if [ -d "$PISYNC_SRC/templates/excludes" ]; then
    echo -e "  ${BLUE}→${NC} Installing exclude templates → ${SHARE_DIR}/excludes/..."
    run_privileged mkdir -p "${SHARE_DIR}/excludes"
    run_privileged cp "$PISYNC_SRC/templates/excludes/"*.exclude "${SHARE_DIR}/excludes/"
    echo -e "  ${GREEN}✓${NC} Exclude templates installed"
fi

# ── Verify ────────────────────────────────────────────────────────────────
echo ""
INSTALLED_VERSION=""
if INSTALLED_VERSION=$(pisync --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); then
    echo -e "  ${GREEN}✓${NC} Verified: pisync ${INSTALLED_VERSION} at $(command -v pisync)"
else
    echo -e "  ${YELLOW}⚠${NC} pisync not found in PATH. You may need to add ${INSTALL_DIR} to your PATH:"
    echo -e "  ${DIM}    export PATH=\"${INSTALL_DIR}:\$PATH\"${NC}"
fi

# ── Next steps ────────────────────────────────────────────────────────────
echo ""
if [ -n "$EXISTING_VERSION" ]; then
    echo -e "  ${BOLD}Upgrade complete!${NC} (${EXISTING_VERSION} → ${INSTALLED_VERSION})"
    echo ""
    echo -e "  If the daemon is running, restart it:"
    echo -e "    ${CYAN}systemctl restart pisync${NC}"
else
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
    echo -e "  ${DIM}Exclude templates available in ${SHARE_DIR}/excludes/${NC}"
fi
echo ""
