#!/usr/bin/env bash
#
# Install rpi-sync systemd units for scheduled sync and node watching
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR}/systemd"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}→${NC} $*"; }
ok() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; exit 1; }

# ── Install Functions ────────────────────────────────────────────────────────
install_timer() {
    info "Installing scheduled sync timer (every 5 minutes)..."

    sudo cp "${SYSTEMD_DIR}/rpi-sync.timer" /etc/systemd/system/
    sudo cp "${SYSTEMD_DIR}/rpi-sync-sync.service" /etc/systemd/system/

    # Update service file with correct user and path
    sudo sed -i "s|User=coreconduit|User=${USER}|g" /etc/systemd/system/rpi-sync-sync.service
    sudo sed -i "s|/home/coreconduit/.rpi-sync|${HOME}/.rpi-sync|g" /etc/systemd/system/rpi-sync-sync.service

    sudo systemctl daemon-reload
    sudo systemctl enable rpi-sync.timer
    sudo systemctl start rpi-sync.timer

    ok "Timer installed and started"
    echo ""
    echo "  View timer: systemctl list-timers rpi-sync.timer"
    echo "  View logs:  journalctl -u rpi-sync-sync.service"
}

install_watcher() {
    info "Installing node availability watcher..."

    sudo cp "${SYSTEMD_DIR}/rpi-sync-watcher.service" /etc/systemd/system/

    # Update service file with correct user and path
    sudo sed -i "s|User=coreconduit|User=${USER}|g" /etc/systemd/system/rpi-sync-watcher.service
    sudo sed -i "s|/home/coreconduit/rpi-sync|${SCRIPT_DIR}|g" /etc/systemd/system/rpi-sync-watcher.service
    sudo sed -i "s|/home/coreconduit/.rpi-sync|${HOME}/.rpi-sync|g" /etc/systemd/system/rpi-sync-watcher.service

    sudo systemctl daemon-reload
    sudo systemctl enable rpi-sync-watcher.service
    sudo systemctl start rpi-sync-watcher.service

    ok "Watcher installed and started"
    echo ""
    echo "  View status: systemctl status rpi-sync-watcher.service"
    echo "  View logs:   journalctl -u rpi-sync-watcher.service -f"
}

install_both() {
    install_timer
    echo ""
    install_watcher
}

uninstall() {
    info "Removing systemd units..."

    sudo systemctl stop rpi-sync.timer 2>/dev/null || true
    sudo systemctl stop rpi-sync-watcher.service 2>/dev/null || true
    sudo systemctl disable rpi-sync.timer 2>/dev/null || true
    sudo systemctl disable rpi-sync-watcher.service 2>/dev/null || true

    sudo rm -f /etc/systemd/system/rpi-sync.timer
    sudo rm -f /etc/systemd/system/rpi-sync-sync.service
    sudo rm -f /etc/systemd/system/rpi-sync-watcher.service

    sudo systemctl daemon-reload

    ok "Systemd units removed"
}

status() {
    echo "Scheduled Sync Timer:"
    systemctl status rpi-sync.timer 2>/dev/null || echo "  Not installed"
    echo ""
    echo "Node Watcher:"
    systemctl status rpi-sync-watcher.service 2>/dev/null || echo "  Not installed"
}

# ── CLI ──────────────────────────────────────────────────────────────────────
case "${1:-help}" in
    timer)
        install_timer
        ;;
    watcher)
        install_watcher
        ;;
    both)
        install_both
        ;;
    uninstall)
        uninstall
        ;;
    status)
        status
        ;;
    *)
        echo "rpi-sync Systemd Installer"
        echo ""
        echo "Usage: $0 {timer|watcher|both|uninstall|status}"
        echo ""
        echo "Commands:"
        echo "  timer     Install scheduled sync timer (every 5 minutes)"
        echo "  watcher   Install node availability watcher"
        echo "  both      Install both timer and watcher"
        echo "  uninstall Remove all systemd units"
        echo "  status    Show current status"
        ;;
esac