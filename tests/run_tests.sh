#!/usr/bin/env bash
# Run pisync test suite
# Usage: ./tests/run_tests.sh [--install-deps] [--verbose] [test_pattern]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

TEST_PATTERN="${1:-}"
BATS_OPTS=()

# ── Install Dependencies ────────────────────────────────────────────────────

install_bats() {
    echo -e "${YELLOW}Installing bats-core...${NC}"

    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y bats
    else
        # Install from source
        BATS_DIR=$(mktemp -d)
        git clone https://github.com/bats-core/bats-core.git "$BATS_DIR"
        cd "$BATS_DIR"
        sudo ./install.sh /usr/local
        rm -rf "$BATS_DIR"
    fi

    echo -e "${GREEN}✓ bats installed${NC}"
}

# ── Check Dependencies ──────────────────────────────────────────────────────

check_deps() {
    if ! command -v bats &>/dev/null; then
        echo -e "${RED}✗ bats not found${NC}"
        echo ""
        echo "Install bats-core:"
        echo "  sudo apt install bats"
        echo "  OR"
        echo "  $0 --install-deps"
        echo ""
        exit 1
    fi

    echo -e "${GREEN}✓ bats found: $(bats --version | head -1)${NC}"
}

# ── Run Tests ───────────────────────────────────────────────────────────────

run_tests() {
    cd "$PROJECT_DIR"

    echo ""
    echo -e "${YELLOW}Running pisync tests...${NC}"
    echo ""

    local test_files=()
    if [ -n "$TEST_PATTERN" ] && [[ "$TEST_PATTERN" != --* ]]; then
        # Run specific test file(s)
        shopt -s nullglob
        test_files=("$SCRIPT_DIR"/"$TEST_PATTERN"*.bats)
        shopt -u nullglob
        if [ ${#test_files[@]} -eq 0 ]; then
            echo -e "${RED}✗ No test files matching: $TEST_PATTERN${NC}"
            exit 1
        fi
    else
        # Run all tests
        test_files=("$SCRIPT_DIR"/*.bats)
    fi

    # Run bats
    bats "${BATS_OPTS[@]}" "${test_files[@]}"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-deps)
                install_bats
                exit 0
                ;;
            --verbose|-v)
                BATS_OPTS+=(--tap)
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--install-deps] [--verbose] [test_pattern]"
                echo ""
                echo "Options:"
                echo "  --install-deps    Install bats-core"
                echo "  --verbose, -v     Verbose TAP output"
                echo "  --help, -h        Show this help"
                echo ""
                echo "Examples:"
                echo "  $0                    # Run all tests"
                echo "  $0 discovery          # Run discovery tests"
                echo "  $0 deploy             # Run deploy tests"
                echo "  $0 connection         # Run connection tests"
                exit 0
                ;;
            *)
                TEST_PATTERN="$1"
                shift
                ;;
        esac
    done

    check_deps
    run_tests
}

main "$@"