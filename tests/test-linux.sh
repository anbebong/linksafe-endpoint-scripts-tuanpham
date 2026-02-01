#!/bin/bash
#
# LINKSAFE Patch Management - Linux Test Suite
#
# Usage: ./test-linux.sh [test_name]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LINUX_DIR="$PROJECT_ROOT/linux"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

skip() {
    echo -e "${YELLOW}○ SKIP${NC}: $1"
}

# Validate JSON output
validate_json() {
    local output="$1"
    local test_name="$2"

    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "$test_name produces valid JSON"
        return 0
    else
        fail "$test_name produces invalid JSON"
        echo "Output was: $output"
        return 1
    fi
}

# Check required fields in JSON
check_json_field() {
    local output="$1"
    local field="$2"
    local test_name="$3"

    if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$field' in d" 2>/dev/null; then
        pass "$test_name has field '$field'"
        return 0
    else
        fail "$test_name missing field '$field'"
        return 1
    fi
}

# ============================================================================
# Test: Library Loading
# ============================================================================
test_library_loading() {
    echo ""
    echo "=== Testing Library Loading ==="

    # Test common.sh
    if source "$PROJECT_ROOT/lib/common.sh" 2>/dev/null; then
        pass "common.sh loads successfully"
    else
        fail "common.sh failed to load"
    fi

    # Test os-detect.sh
    if source "$PROJECT_ROOT/lib/os-detect.sh" 2>/dev/null; then
        pass "os-detect.sh loads successfully"
    else
        fail "os-detect.sh failed to load"
    fi

    # Test hooks-runner.sh
    if source "$PROJECT_ROOT/lib/hooks-runner.sh" 2>/dev/null; then
        pass "hooks-runner.sh loads successfully"
    else
        fail "hooks-runner.sh failed to load"
    fi
}

# ============================================================================
# Test: OS Detection
# ============================================================================
test_os_detection() {
    echo ""
    echo "=== Testing OS Detection ==="

    source "$PROJECT_ROOT/lib/os-detect.sh"

    # Should detect OS
    if [[ -n "$DETECTED_OS" ]]; then
        pass "OS detected: $DETECTED_OS"
    else
        fail "OS not detected"
    fi

    # Should detect OS family
    if [[ -n "$OS_FAMILY" ]]; then
        pass "OS family detected: $OS_FAMILY"
    else
        fail "OS family not detected"
    fi

    # Should detect package manager
    if [[ -n "$PKG_MANAGER" ]]; then
        pass "Package manager detected: $PKG_MANAGER"
    else
        fail "Package manager not detected"
    fi

    # Package manager should be valid
    case "$PKG_MANAGER" in
        apt|dnf|yum|zypper)
            pass "Package manager is supported: $PKG_MANAGER"
            ;;
        *)
            skip "Package manager may be unsupported: $PKG_MANAGER"
            ;;
    esac
}

# ============================================================================
# Test: JSON Helper Functions
# ============================================================================
test_json_helpers() {
    echo ""
    echo "=== Testing JSON Helpers ==="

    source "$PROJECT_ROOT/lib/common.sh"

    # Test json_escape
    local escaped
    escaped=$(json_escape 'test "quoted" string')
    if [[ "$escaped" == 'test \"quoted\" string' ]]; then
        pass "json_escape handles quotes"
    else
        fail "json_escape failed: got '$escaped'"
    fi

    # Test json_string
    local json_str
    json_str=$(json_string "key" "value")
    if [[ "$json_str" == '"key": "value"' ]]; then
        pass "json_string produces correct format"
    else
        fail "json_string failed: got '$json_str'"
    fi

    # Test json_bool
    local json_true json_false
    json_true=$(json_bool "flag" true)
    json_false=$(json_bool "flag" false)

    if [[ "$json_true" == '"flag": true' ]] && [[ "$json_false" == '"flag": false' ]]; then
        pass "json_bool produces correct format"
    else
        fail "json_bool failed"
    fi
}

# ============================================================================
# Test: Check Updates Script
# ============================================================================
test_check_updates() {
    echo ""
    echo "=== Testing check-updates.sh ==="

    local script="$LINUX_DIR/actions/check-updates.sh"

    if [[ ! -x "$script" ]]; then
        skip "check-updates.sh not executable or not found"
        return
    fi

    # Test help
    if "$script" --help 2>&1 | grep -q "Usage"; then
        pass "check-updates.sh --help works"
    else
        fail "check-updates.sh --help failed"
    fi

    # Test dry run (no actual update check without root)
    if [[ $EUID -eq 0 ]]; then
        local output
        output=$("$script" 2>/dev/null || true)
        validate_json "$output" "check-updates.sh"
        check_json_field "$output" "hostname" "check-updates.sh"
        check_json_field "$output" "timestamp" "check-updates.sh"
    else
        skip "check-updates.sh requires root for full test"
    fi
}

# ============================================================================
# Test: Check Reboot Script
# ============================================================================
test_check_reboot() {
    echo ""
    echo "=== Testing check-reboot.sh ==="

    local script="$LINUX_DIR/actions/check-reboot.sh"

    if [[ ! -x "$script" ]]; then
        skip "check-reboot.sh not executable or not found"
        return
    fi

    # Test help
    if "$script" --help 2>&1 | grep -q "Usage"; then
        pass "check-reboot.sh --help works"
    else
        fail "check-reboot.sh --help failed"
    fi

    # Test execution
    local output
    output=$("$script" 2>/dev/null || true)
    validate_json "$output" "check-reboot.sh"
    check_json_field "$output" "reboot_required" "check-reboot.sh"
}

# ============================================================================
# Test: List Installed Script
# ============================================================================
test_list_installed() {
    echo ""
    echo "=== Testing list-installed.sh ==="

    local script="$LINUX_DIR/actions/list-installed.sh"

    if [[ ! -x "$script" ]]; then
        skip "list-installed.sh not executable or not found"
        return
    fi

    # Test help
    if "$script" --help 2>&1 | grep -q "Usage"; then
        pass "list-installed.sh --help works"
    else
        fail "list-installed.sh --help failed"
    fi

    # Test execution with limit
    local output
    output=$("$script" --limit 5 2>/dev/null || true)
    validate_json "$output" "list-installed.sh"
    check_json_field "$output" "packages" "list-installed.sh"
}

# ============================================================================
# Test: Hook Validation
# ============================================================================
test_hooks() {
    echo ""
    echo "=== Testing Hooks System ==="

    source "$PROJECT_ROOT/lib/hooks-runner.sh"

    # Check hook directories exist
    local hook_dirs=(
        "$LINUX_DIR/hooks.d/pre-upgrade"
        "$LINUX_DIR/hooks.d/pre-reboot"
        "$LINUX_DIR/hooks.d/post-upgrade"
    )

    for dir in "${hook_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            pass "Hook directory exists: $(basename "$dir")"
        else
            fail "Hook directory missing: $dir"
        fi
    done

    # Count hook scripts
    local hook_count
    hook_count=$(find "$LINUX_DIR/hooks.d" -name "*.sh" 2>/dev/null | wc -l)
    pass "Found $hook_count hook scripts"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "========================================"
    echo "LINKSAFE Patch Management - Linux Tests"
    echo "========================================"
    echo "Project Root: $PROJECT_ROOT"
    echo "Date: $(date)"
    echo ""

    # Run specific test or all
    if [[ -n "$1" ]]; then
        case "$1" in
            library) test_library_loading ;;
            os) test_os_detection ;;
            json) test_json_helpers ;;
            check) test_check_updates ;;
            reboot) test_check_reboot ;;
            installed) test_list_installed ;;
            hooks) test_hooks ;;
            *)
                echo "Unknown test: $1"
                echo "Available: library, os, json, check, reboot, installed, hooks"
                exit 1
                ;;
        esac
    else
        # Run all tests
        test_library_loading
        test_os_detection
        test_json_helpers
        test_check_updates
        test_check_reboot
        test_list_installed
        test_hooks
    fi

    # Summary
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
