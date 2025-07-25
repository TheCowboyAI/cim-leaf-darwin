#!/usr/bin/env bash
# Simple validation test for the template

set -euo pipefail

echo "=== Validating CIM Leaf Darwin Template ==="
echo ""

# Track results
ERRORS=0

# Function to check file
check_file() {
    if [ -f "$1" ]; then
        echo "✓ Found: $1"
    else
        echo "✗ Missing: $1"
        ((ERRORS++))
    fi
}

# Function to check directory
check_dir() {
    if [ -d "$1" ]; then
        echo "✓ Found: $1/"
    else
        echo "✗ Missing: $1/"
        ((ERRORS++))
    fi
}

echo "Checking required files..."
echo ""

# Core files
check_file "flake.nix"
check_file "darwin.nix"
check_file "home.nix"
check_file "leaf.config.json.template"
check_file ".envrc"
check_file "README.md"
check_file ".gitignore"

echo ""
echo "Checking scripts..."
echo ""

# Scripts
check_file "scripts/setup_leaf.sh"
check_file "scripts/extract_inventory.sh"
check_file "scripts/generate_config.sh"
check_file "scripts/deploy_host.sh"
# sync_domain.sh is created by setup_leaf.sh
check_file "scripts/health_check.sh"
check_file "scripts/backup_restore.sh"
check_file "scripts/maintenance.sh"

echo ""
echo "Checking modules..."
echo ""

# Modules
check_file "modules/nats.nix"
check_file "modules/monitoring.nix"
check_file "modules/security.nix"

echo ""
echo "Checking directories..."
echo ""

# Directories
check_dir "modules"
check_dir "modules/domains"
check_dir "scripts"
check_dir "inventory"
check_dir "hosts"
check_dir "doc"
check_dir ".claude"
check_dir "examples"
check_dir ".github"
check_dir "test"

echo ""
echo "Checking template placeholders..."
echo ""

# Check for placeholders in template
if grep -q "LEAF_NAME\|DOMAIN_NAME\|YOUR_ORG" leaf.config.json.template; then
    echo "✓ Template placeholders found"
else
    echo "✗ Template placeholders missing"
    ((ERRORS++))
fi

echo ""
echo "Checking script permissions..."
echo ""

# Check if scripts are executable
for script in scripts/*.sh; do
    if [ -x "$script" ]; then
        echo "✓ Executable: $script"
    else
        echo "✗ Not executable: $script"
        ((ERRORS++))
    fi
done

echo ""
echo "=== Summary ==="
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "✓ All checks passed! Template is ready."
    echo ""
    echo "Next steps:"
    echo "1. Commit and push to GitHub"
    echo "2. Mark repository as a template in Settings"
    echo "3. Test by clicking 'Use this template'"
else
    echo "✗ Found $ERRORS errors. Please fix before using as template."
    exit 1
fi