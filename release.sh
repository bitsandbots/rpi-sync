#!/usr/bin/env bash
# ============================================================================
# PiSync Release Script
# CoreConduit Consulting Services | MIT License
# ============================================================================
# Bumps the version, builds a distributable tarball, and tags the release.
#
# Usage:
#   ./release.sh <version>          Full release (bump, build, tag, commit)
#   ./release.sh <version> --dry-run Preview without writing anything
#   ./release.sh --current          Print current version and exit
#
# Examples:
#   ./release.sh 1.1.0
#   ./release.sh 1.1.0 --dry-run
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

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
PISYNC_SCRIPT="$REPO_ROOT/pisync"
DIST_DIR="$REPO_ROOT/dist"
DRY_RUN=false
NEW_VERSION=""

info()  { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
error() { echo -e "  ${RED}✗${NC} $*" >&2; }
step()  { echo -e "  ${BLUE}→${NC} $*"; }

# ── Banner ────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Pi${ORANGE}Sync${NC} ${BOLD}Release Builder${NC}"
echo -e "  ${DIM}CoreConduit Consulting Services${NC}"
echo ""

# ── Parse arguments ───────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    error "Version argument required."
    echo "  Usage: $0 <version> [--dry-run]"
    echo "  Usage: $0 --current"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --current)
            CURRENT=$(grep '^PISYNC_VERSION=' "$PISYNC_SCRIPT" | head -1 | cut -d'"' -f2)
            echo "  Current version: ${CURRENT}"
            exit 0
            ;;
        --help|-h)
            echo "  Usage: $0 <version> [--dry-run]"
            exit 0
            ;;
        [0-9]*)
            NEW_VERSION="$1"
            shift
            ;;
        *)
            error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$NEW_VERSION" ]; then
    error "No version specified."
    exit 1
fi

# ── Validate version format ───────────────────────────────────────────────
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Version must be semver: MAJOR.MINOR.PATCH (e.g. 1.1.0)"
    exit 1
fi

CURRENT_VERSION=$(grep '^PISYNC_VERSION=' "$PISYNC_SCRIPT" | head -1 | cut -d'"' -f2)
RELEASE_TAG="v${NEW_VERSION}"
TARBALL_NAME="pisync-${RELEASE_TAG}.tar.gz"

echo -e "  ${DIM}Current version : ${CURRENT_VERSION}${NC}"
echo -e "  ${DIM}New version     : ${NEW_VERSION}${NC}"
echo -e "  ${DIM}Release tag     : ${RELEASE_TAG}${NC}"
echo -e "  ${DIM}Output          : dist/${TARBALL_NAME}${NC}"
[ "$DRY_RUN" = true ] && echo -e "  ${YELLOW}DRY RUN — no files will be modified${NC}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────
step "Pre-flight checks..."

# Must be run from repo root
if [ ! -f "$PISYNC_SCRIPT" ]; then
    error "pisync script not found at $PISYNC_SCRIPT"
    exit 1
fi

# Git must be clean
if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
    DIRTY=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)
    if [ -n "$DIRTY" ]; then
        error "Working tree is not clean. Commit or stash changes first."
        git -C "$REPO_ROOT" status --short
        exit 1
    fi

    # Tag must not already exist
    if git -C "$REPO_ROOT" rev-parse "$RELEASE_TAG" &>/dev/null; then
        error "Tag ${RELEASE_TAG} already exists."
        exit 1
    fi
    HAS_GIT=true
else
    warn "Not a git repository — skipping tag creation"
    HAS_GIT=false
fi

# Version must not be a downgrade
IFS='.' read -r cur_maj cur_min cur_pat <<< "$CURRENT_VERSION"
IFS='.' read -r new_maj new_min new_pat <<< "$NEW_VERSION"
if (( new_maj < cur_maj )) || \
   (( new_maj == cur_maj && new_min < cur_min )) || \
   (( new_maj == cur_maj && new_min == cur_min && new_pat <= cur_pat )); then
    error "New version ${NEW_VERSION} is not greater than current ${CURRENT_VERSION}"
    exit 1
fi

info "Pre-flight checks passed"

# ── Bump version in pisync script ─────────────────────────────────────────
step "Bumping version: ${CURRENT_VERSION} → ${NEW_VERSION}..."

if [ "$DRY_RUN" = false ]; then
    sed -i "s/^PISYNC_VERSION=\"${CURRENT_VERSION}\"/PISYNC_VERSION=\"${NEW_VERSION}\"/" "$PISYNC_SCRIPT"
    # Verify the bump applied
    APPLIED=$(grep '^PISYNC_VERSION=' "$PISYNC_SCRIPT" | head -1 | cut -d'"' -f2)
    if [ "$APPLIED" != "$NEW_VERSION" ]; then
        error "Version bump failed — expected ${NEW_VERSION}, got ${APPLIED}"
        exit 1
    fi
    # Syntax check after edit
    bash -n "$PISYNC_SCRIPT" || { error "Syntax error in pisync after version bump"; exit 1; }
    info "Version bumped and syntax verified"
else
    info "[dry-run] Would bump PISYNC_VERSION to ${NEW_VERSION}"
fi

# ── Build tarball ─────────────────────────────────────────────────────────
step "Building ${TARBALL_NAME}..."

if [ "$DRY_RUN" = false ]; then
    mkdir -p "$DIST_DIR"

    # Build into a versioned subdirectory inside the tarball
    STAGE_DIR=$(mktemp -d)
    STAGE_PKG="$STAGE_DIR/pisync-${NEW_VERSION}"
    mkdir -p "$STAGE_PKG"

    # Files to include
    cp "$REPO_ROOT/pisync"          "$STAGE_PKG/pisync"
    cp "$REPO_ROOT/install.sh"      "$STAGE_PKG/install.sh"
    cp "$REPO_ROOT/healthcheck.sh"  "$STAGE_PKG/healthcheck.sh"
    cp "$REPO_ROOT/README.md"       "$STAGE_PKG/README.md"
    cp "$REPO_ROOT/LICENSE"         "$STAGE_PKG/LICENSE"
    cp -r "$REPO_ROOT/templates"    "$STAGE_PKG/templates"
    cp -r "$REPO_ROOT/docs"         "$STAGE_PKG/docs"

    chmod +x "$STAGE_PKG/pisync" "$STAGE_PKG/install.sh" "$STAGE_PKG/healthcheck.sh"

    # Create tarball with reproducible mtime
    tar -czf "$DIST_DIR/$TARBALL_NAME" \
        -C "$STAGE_DIR" \
        --owner=0 --group=0 \
        "pisync-${NEW_VERSION}"

    rm -rf "$STAGE_DIR"

    # Generate SHA256 checksum
    (cd "$DIST_DIR" && sha256sum "$TARBALL_NAME" > "${TARBALL_NAME}.sha256")

    TARBALL_SIZE=$(du -sh "$DIST_DIR/$TARBALL_NAME" | cut -f1)
    info "Built dist/${TARBALL_NAME} (${TARBALL_SIZE})"
    info "Checksum: dist/${TARBALL_NAME}.sha256"
    cat "$DIST_DIR/${TARBALL_NAME}.sha256"
else
    info "[dry-run] Would build dist/${TARBALL_NAME}"
    echo -e "    ${DIM}Contents: pisync, install.sh, healthcheck.sh, README.md, LICENSE, templates/, docs/${NC}"
fi

# ── Commit version bump ───────────────────────────────────────────────────
if [ "$HAS_GIT" = true ]; then
    step "Committing version bump..."

    if [ "$DRY_RUN" = false ]; then
        git -C "$REPO_ROOT" add "$PISYNC_SCRIPT"
        git -C "$REPO_ROOT" commit -m "chore(release): bump version to ${NEW_VERSION}"
        info "Committed version bump"
    else
        info "[dry-run] Would commit: chore(release): bump version to ${NEW_VERSION}"
    fi

    # ── Tag the release ───────────────────────────────────────────────────
    step "Tagging ${RELEASE_TAG}..."

    if [ "$DRY_RUN" = false ]; then
        git -C "$REPO_ROOT" tag -a "$RELEASE_TAG" \
            -m "PiSync ${NEW_VERSION} — LAN Project Sync for Pi Networks"
        info "Tagged ${RELEASE_TAG}"
    else
        info "[dry-run] Would tag: ${RELEASE_TAG}"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "  ${DIM}──────────────────────────────────────────────${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "  ${YELLOW}Dry run complete — no changes made.${NC}"
    echo ""
    echo -e "  Run without --dry-run to execute the release."
else
    echo -e "  ${GREEN}${BOLD}Release ${RELEASE_TAG} ready!${NC}"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "    ${CYAN}git push && git push --tags${NC}          Push to remote"
    echo -e "    ${CYAN}cat dist/${TARBALL_NAME}.sha256${NC}"
    if [ "$HAS_GIT" = true ]; then
        echo -e ""
        echo -e "  ${DIM}To distribute:${NC}"
        echo -e "    ${DIM}Attach dist/${TARBALL_NAME} to the GitHub release for tag ${RELEASE_TAG}${NC}"
    fi
fi
echo ""
