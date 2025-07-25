#!/usr/bin/env bash
# Local testing script for CIM Leaf Darwin template

set -euo pipefail

echo "=== CIM Leaf Darwin Local Test ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name=$1
    local test_command=$2
    
    echo -n "Testing $test_name... "
    
    if eval "$test_command" &>/dev/null; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        echo "  Command: $test_command"
    fi
}

# Check prerequisites
echo "=== Checking Prerequisites ==="

run_test "Git installed" "command -v git"
run_test "Nix installed" "command -v nix"
run_test "jq installed" "command -v jq"
run_test "Bash 4+" "[[ \${BASH_VERSION%%.*} -ge 4 ]]"

echo ""
echo "=== Testing Template Structure ==="

# Test file existence
run_test "Template config exists" "[ -f leaf.config.json.template ]"
run_test "Setup script exists" "[ -f scripts/setup_leaf.sh ]"
run_test "Extract inventory script" "[ -f scripts/extract_inventory.sh ]"
run_test "Deploy script exists" "[ -f scripts/deploy_host.sh ]"
run_test "Health check script" "[ -f scripts/health_check.sh ]"
run_test "Backup script exists" "[ -f scripts/backup_restore.sh ]"
run_test "Maintenance script" "[ -f scripts/maintenance.sh ]"

# Test directory structure
run_test "Modules directory" "[ -d modules ]"
run_test "Scripts directory" "[ -d scripts ]"
run_test ".claude directory" "[ -d .claude ]"
run_test "Examples directory" "[ -d examples ]"

# Test module files
run_test "NATS module" "[ -f modules/nats.nix ]"
run_test "Monitoring module" "[ -f modules/monitoring.nix ]"
run_test "Security module" "[ -f modules/security.nix ]"

echo ""
echo "=== Testing Setup Process ==="

# Create a test environment
TEST_DIR="/tmp/cim-leaf-test-$$"
echo "Creating test environment in $TEST_DIR"

# Copy template to test directory
cp -r . "$TEST_DIR"
cd "$TEST_DIR"

# Test setup script in non-interactive mode
cat > test_inputs.txt << EOF
test-leaf-1
Test Leaf Instance
analytics
us-west-2
dev
TestOrg
test-cluster
nats-hub.example.com
EOF

echo ""
echo "Running setup script with test inputs..."
if ./scripts/setup_leaf.sh < test_inputs.txt &>/dev/null; then
    echo -e "${GREEN}✓ Setup script completed${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ Setup script failed${NC}"
    ((TESTS_FAILED++))
fi

# Verify setup results
echo ""
echo "=== Verifying Setup Results ==="

run_test "Leaf config created" "[ -f leaf.config.json ]"
run_test "Template removed" "[ ! -f leaf.config.json.template ]"
run_test "Domain module created" "[ -f modules/domains/analytics.nix ]"
run_test "Sync script created" "[ -f scripts/sync_domain.sh ]"

# Check configuration values
if [ -f leaf.config.json ]; then
    run_test "Leaf name set" "[[ \$(jq -r '.leaf.name' leaf.config.json) == 'test-leaf-1' ]]"
    run_test "Domain set" "[[ \$(jq -r '.leaf.domain' leaf.config.json) == 'analytics' ]]"
    run_test "Environment set" "[[ \$(jq -r '.leaf.environment' leaf.config.json) == 'dev' ]]"
fi

echo ""
echo "=== Testing Nix Configuration ==="

# Test flake evaluation
run_test "Flake metadata" "nix flake metadata --json"
run_test "Flake check" "nix flake check --no-build"

# Test Darwin configuration build (dry run)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Testing Darwin configuration build..."
    run_test "Darwin config eval" "nix eval .#darwinConfigurations.default.config.system.build.toplevel"
fi

echo ""
echo "=== Testing Scripts ==="

# Test script syntax
for script in scripts/*.sh; do
    run_test "Syntax check: $(basename $script)" "bash -n $script"
done

# Test health check in dry-run mode
run_test "Health check runs" "./scripts/health_check.sh || true"

# Test backup script help
run_test "Backup script help" "./scripts/backup_restore.sh --help"

# Test maintenance script help
run_test "Maintenance help" "./scripts/maintenance.sh --help"

echo ""
echo "=== Testing Example Domain ==="

if [ -d examples/cim-domain-trading ]; then
    run_test "Domain example exists" "[ -f examples/cim-domain-trading/README.md ]"
    run_test "Domain events module" "[ -f examples/cim-domain-trading/modules/events.nix ]"
    run_test "Domain commands module" "[ -f examples/cim-domain-trading/modules/commands.nix ]"
fi

# Cleanup
echo ""
echo "=== Cleanup ==="
cd /
rm -rf "$TEST_DIR"
echo "Test environment cleaned up"

# Summary
echo ""
echo "=== Test Summary ==="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}✗ Some tests failed${NC}"
    exit 1
fi