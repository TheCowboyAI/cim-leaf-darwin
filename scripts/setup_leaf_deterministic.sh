#!/usr/bin/env bash
# Deterministic setup script that reads from Nix configuration

set -euo pipefail

# Source event store functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/event_store.sh"

echo "=== CIM Leaf Deterministic Setup ==="
echo ""

# Check if we're in template mode
if [ -f "leaf.config.json.template" ]; then
    echo "This is a template repository."
    echo "First, update leaf-config.nix with your configuration values."
    echo ""
    echo "Replace all placeholders (LEAF_NAME, DOMAIN_NAME, etc.) in:"
    echo "  - leaf-config.nix"
    echo "  - topology.nix (if adding to global topology)"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Extract configuration from Nix
echo "Reading configuration from leaf-config.nix..."

# Use nix eval to extract configuration values
LEAF_NAME=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).leaf.name')
LEAF_DESC=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).leaf.description')
DOMAIN_NAME=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).leaf.domain')
REGION=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).leaf.region')
ENVIRONMENT=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).leaf.environment')
CLUSTER_NAME=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).nats.cluster.name')
PRIMARY_HOST=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).deployment.primary.hostname')
PRIMARY_IP=$(nix eval --raw --impure --expr '(import ./leaf-config.nix { lib = (import <nixpkgs> {}).lib; }).deployment.primary.ip')

# Check for placeholder values
if [[ "$LEAF_NAME" == *"LEAF_NAME"* ]] || [[ "$DOMAIN_NAME" == *"DOMAIN_NAME"* ]]; then
    echo "Error: Configuration still contains placeholder values!"
    echo "Please update leaf-config.nix with actual values."
    exit 1
fi

# Display configuration
echo ""
echo "Configuration loaded:"
echo "  Leaf Name: $LEAF_NAME"
echo "  Domain: $DOMAIN_NAME"
echo "  Region: $REGION"
echo "  Environment: $ENVIRONMENT"
echo "  Cluster: $CLUSTER_NAME"
echo "  Primary Host: $PRIMARY_HOST ($PRIMARY_IP)"
echo ""

# Confirm configuration
read -p "Is this configuration correct? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled. Please update leaf-config.nix and try again."
    exit 1
fi

# Start setup correlation
CORRELATION_ID=$(generate_correlation_id)

# Emit setup started event
emit_event "leaf.setup.started" "$LEAF_NAME" "leaf" \
    "$(jq -n \
        --arg name "$LEAF_NAME" \
        --arg domain "$DOMAIN_NAME" \
        --arg env "$ENVIRONMENT" \
        '{
            status: "starting",
            leaf_name: $name,
            domain: $domain,
            environment: $env,
            config_source: "nix"
        }')" \
    "$CORRELATION_ID"

# Create domain module
echo "Creating domain module..."
mkdir -p modules/domains

cat > "modules/domains/${DOMAIN_NAME}.nix" << EOF
# Domain-specific configuration for ${DOMAIN_NAME}
# Auto-generated from leaf-config.nix
{ config, lib, pkgs, leafConfig, ... }:

let
  cfg = leafConfig;
in
{
  # Domain-specific NATS subjects
  environment.variables = {
    CIM_DOMAIN = "${DOMAIN_NAME}";
    CIM_LEAF_NAME = "${LEAF_NAME}";
    CIM_ENVIRONMENT = "${ENVIRONMENT}";
    
    # NATS subject prefixes from configuration
    NATS_EVENT_SUBJECT = cfg.nats.jetstream.streams."\${lib.toUpper cfg.leaf.domain}_EVENTS".subjects;
    NATS_COMMAND_SUBJECT = cfg.nats.jetstream.streams."\${lib.toUpper cfg.leaf.domain}_COMMANDS".subjects;
  };
  
  # Import domain-specific packages if needed
  # environment.systemPackages = with pkgs; [
  #   # Add domain-specific tools here
  # ];
}
EOF

# Create JSON representation for compatibility
echo "Creating JSON configuration..."
cat > leaf.config.json << EOF
{
  "leaf": {
    "name": "$LEAF_NAME",
    "description": "$LEAF_DESC",
    "domain": "$DOMAIN_NAME",
    "region": "$REGION",
    "environment": "$ENVIRONMENT"
  },
  "deployment": {
    "primary": {
      "hostname": "$PRIMARY_HOST",
      "ip": "$PRIMARY_IP"
    }
  },
  "_note": "This file is generated from leaf-config.nix. Do not edit directly."
}
EOF

# Update git configuration
git config user.name "CIM Leaf ${LEAF_NAME}"
git config user.email "cim-leaf-${LEAF_NAME}@${DOMAIN_NAME}.local"

# Remove template file if it exists
[ -f "leaf.config.json.template" ] && rm -f "leaf.config.json.template"

# Emit setup completed event
emit_event "leaf.setup.completed" "$LEAF_NAME" "leaf" \
    "$(jq -n \
        --arg name "$LEAF_NAME" \
        --arg domain "$DOMAIN_NAME" \
        '{
            leaf_name: $name,
            domain: $domain,
            status: "completed",
            config_source: "nix"
        }')" \
    "$CORRELATION_ID"

# Build initial projections
echo "Building initial projections..."
source "${SCRIPT_DIR}/../lib/projections.sh"
update_all_projections

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Leaf ${LEAF_NAME} has been configured for domain ${DOMAIN_NAME}"
echo ""
echo "Configuration source: leaf-config.nix (deterministic)"
echo ""
echo "Next steps:"
echo "1. Review the generated files"
echo "2. Commit your configuration:"
echo "   git add -A && git commit -m 'Configure ${LEAF_NAME} for ${DOMAIN_NAME} domain'"
echo "3. Deploy to ${PRIMARY_HOST}:"
echo "   ./scripts/deploy_host.sh ${PRIMARY_HOST} ${PRIMARY_IP}"
echo ""
echo "To modify configuration, edit leaf-config.nix and run:"
echo "   nix flake check"