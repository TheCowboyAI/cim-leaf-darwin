#!/usr/bin/env bash
# Setup script for new CIM leaf instances from template

set -euo pipefail

echo "=== CIM Leaf Setup ==="
echo ""

# Check if this is still the template
if [ -f "leaf.config.json.template" ] && [ ! -f "leaf.config.json" ]; then
    echo "Setting up new leaf from template..."
else
    echo "This leaf has already been configured."
    echo "To reconfigure, delete leaf.config.json first."
    exit 1
fi

# Gather configuration
read -p "Leaf name (e.g., tokyo-prod-1): " LEAF_NAME
read -p "Leaf description: " LEAF_DESCRIPTION
read -p "Domain name (e.g., trading, analytics): " DOMAIN_NAME
read -p "Region code (e.g., us-west-2, eu-central-1): " REGION_CODE
read -p "Environment (dev/staging/prod): " ENVIRONMENT
read -p "GitHub organization: " GITHUB_ORG
read -p "NATS cluster name: " CLUSTER_NAME
read -p "Upstream NATS host (IP or hostname): " UPSTREAM_HOST

# Create leaf configuration
cp leaf.config.json.template leaf.config.json

# Platform-specific sed (macOS vs Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE="sed -i ''"
else
    SED_INPLACE="sed -i"
fi

# Replace placeholders
$SED_INPLACE "s/LEAF_NAME/${LEAF_NAME}/g" leaf.config.json
$SED_INPLACE "s/LEAF_DESCRIPTION/${LEAF_DESCRIPTION}/g" leaf.config.json
$SED_INPLACE "s/DOMAIN_NAME/${DOMAIN_NAME}/g" leaf.config.json
$SED_INPLACE "s/REGION_CODE/${REGION_CODE}/g" leaf.config.json
$SED_INPLACE "s/ENVIRONMENT/${ENVIRONMENT}/g" leaf.config.json
$SED_INPLACE "s/YOUR_ORG/${GITHUB_ORG}/g" leaf.config.json
$SED_INPLACE "s/CIM_CLUSTER_NAME/${CLUSTER_NAME}/g" leaf.config.json
$SED_INPLACE "s/UPSTREAM_HOST/${UPSTREAM_HOST}/g" leaf.config.json
$SED_INPLACE "s/HOST_NAME/${LEAF_NAME}/g" leaf.config.json
$SED_INPLACE "s/HOST_IP/PENDING/g" leaf.config.json

# Update flake description
$SED_INPLACE "s/cim-leaf-darwin - Remote deployable CIM leaf node for macOS/cim-leaf-${LEAF_NAME} - ${LEAF_DESCRIPTION}/g" flake.nix

# Create domain module directory
mkdir -p modules/domains

# Generate domain configuration module
cat > modules/domains/${DOMAIN_NAME}.nix << EOF
# Domain-specific configuration for ${DOMAIN_NAME}
{ config, lib, pkgs, ... }:

{
  # Domain-specific NATS subjects
  environment.variables = {
    CIM_DOMAIN = "${DOMAIN_NAME}";
    CIM_LEAF_NAME = "${LEAF_NAME}";
    
    # NATS subject prefixes for this domain
    NATS_COMMAND_SUBJECT = "cim.${DOMAIN_NAME}.commands.>";
    NATS_EVENT_SUBJECT = "cim.${DOMAIN_NAME}.events.>";
    NATS_QUERY_SUBJECT = "cim.${DOMAIN_NAME}.queries.>";
  };
  
  # Domain-specific packages
  # environment.systemPackages = with pkgs; [
  #   # Add domain-specific tools here
  # ];
}
EOF

# Update .gitignore
echo "" >> .gitignore
echo "# Leaf configuration (contains deployment specifics)" >> .gitignore
echo "leaf.config.json" >> .gitignore

# Create domain integration script
cat > scripts/sync_domain.sh << 'EOF'
#!/usr/bin/env bash
# Sync domain modules from cim-domain repository

set -euo pipefail

if [ ! -f "leaf.config.json" ]; then
    echo "Error: leaf.config.json not found. Run setup_leaf.sh first."
    exit 1
fi

# Extract domain repository URL
DOMAIN_REPO=$(jq -r '.cim_domain.repository' leaf.config.json)
DOMAIN_NAME=$(jq -r '.leaf.domain' leaf.config.json)

echo "Syncing domain modules from ${DOMAIN_REPO}..."

# Clone or update domain repository
if [ -d ".domain-sync" ]; then
    cd .domain-sync && git pull && cd ..
else
    git clone "${DOMAIN_REPO}" .domain-sync
fi

# Copy domain modules
echo "Copying domain modules..."
mkdir -p modules/domains/${DOMAIN_NAME}
cp -r .domain-sync/modules/* modules/domains/${DOMAIN_NAME}/ 2>/dev/null || true

# Copy domain-specific configurations if they exist
if [ -d ".domain-sync/leaf-configs" ]; then
    cp -r .domain-sync/leaf-configs/* . 2>/dev/null || true
fi

echo "Domain sync complete!"
EOF

chmod +x scripts/sync_domain.sh

# Update git configuration
git config user.name "CIM Leaf ${LEAF_NAME}"
git config user.email "cim-leaf-${LEAF_NAME}@${DOMAIN_NAME}.local"

# Remove template file
rm leaf.config.json.template

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Leaf ${LEAF_NAME} has been configured for domain ${DOMAIN_NAME}"
echo ""
echo "Next steps:"
echo "1. Review and commit the configuration:"
echo "   git add -A && git commit -m 'Initialize ${LEAF_NAME} for ${DOMAIN_NAME} domain'"
echo ""
echo "2. Update the repository name on GitHub to: cim-leaf-${LEAF_NAME}"
echo ""
echo "3. Extract inventory from target hosts:"
echo "   ./scripts/extract_inventory.sh <host_ip>"
echo ""
echo "4. Sync domain modules (if domain repo exists):"
echo "   ./scripts/sync_domain.sh"
echo ""
echo "5. Deploy to hosts:"
echo "   ./scripts/deploy_host.sh <hostname> <ip>"
echo ""
echo "6. Run health checks after deployment:"
echo "   ./scripts/health_check.sh"
echo ""
echo "7. Set up monitoring (optional):"
echo "   Visit http://<host>:3000 for Grafana dashboard"
echo ""
echo "8. Configure backups:"
echo "   ./scripts/backup_restore.sh backup"