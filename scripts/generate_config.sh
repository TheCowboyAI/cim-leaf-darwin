#!/usr/bin/env bash
# Generate nix-darwin configuration from inventory

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <hostname>"
    echo "Example: $0 mac-studio-1"
    exit 1
fi

HOSTNAME="$1"
INVENTORY_FILE="inventory/${HOSTNAME}/latest.json"

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "Error: No inventory found for $HOSTNAME"
    echo "Run: nix run .#extract-inventory -- <ip_address> first"
    exit 1
fi

echo "Generating configuration for $HOSTNAME from inventory..."

# Extract key information from inventory
SERIAL=$(jq -r '.system_info.serial_number' "$INVENTORY_FILE")
MODEL=$(jq -r '.system_info.model' "$INVENTORY_FILE")
ARCH=$(jq -r '.system_info.architecture' "$INVENTORY_FILE")
MEMORY_GB=$(jq -r '.hardware.memory_gb' "$INVENTORY_FILE")

# Determine system architecture for Nix
if [[ "$ARCH" == "arm64" ]]; then
    NIX_SYSTEM="aarch64-darwin"
else
    NIX_SYSTEM="x86_64-darwin"
fi

# Create host-specific directory
mkdir -p "hosts/${HOSTNAME}"

# Generate host-specific Nix configuration
cat > "hosts/${HOSTNAME}/configuration.nix" << EOF
# Host-specific configuration for ${HOSTNAME}
# Serial: ${SERIAL}
# Model: ${MODEL}
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
{ config, pkgs, lib, leafConfig, ... }:

let
  # Import hardware configuration from inventory
  hardwareConfig = import ../../inventory/${HOSTNAME}/hardware.nix { inherit lib; };
in
{
  # Host identification
  networking.hostName = "${HOSTNAME}";
  
  # Import hardware-based optimizations
  imports = [ ];
  
  # Nix settings based on hardware
  nix.settings = {
    max-jobs = if hardwareConfig.hardware.cpu.cores >= 16 then 16
               else if hardwareConfig.hardware.cpu.cores >= 8 then 8
               else 4;
    cores = 0; # Use all available cores
  };
  
  # System-specific overrides
  system.defaults = {
    # Performance tuning based on hardware
    NSGlobalDomain = {
      # Faster UI if we have good specs
      NSWindowResizeTime = if hardwareConfig.hardware.memory.sizeGB >= 32 then 0.001 else 0.1;
    };
  };
  
  # NATS overrides based on hardware capabilities
  services.nats = {
    # Override JetStream settings based on available resources
    settings = {
      jetstream = {
        max_memory_store = hardwareConfig.storage.jetstream.maxMemoryStore;
        max_file_store = hardwareConfig.storage.jetstream.maxFileStore;
      };
      
      # Connection limits based on CPU
      max_connections = hardwareConfig.performance.nats.maxConnections;
      max_pending = hardwareConfig.performance.nats.maxPending;
    };
  };
  
  # Monitoring retention based on storage
  services.prometheus.retentionTime = lib.mkDefault hardwareConfig.monitoring.prometheus.retention;
  
  # Backup settings from hardware analysis
  services.backup = {
    retention = {
      days = hardwareConfig.storage.backup.retentionDays;
    };
  };
}
EOF

# The flake.nix now automatically discovers hosts with inventory
echo ""
echo "Host configuration generated at: hosts/${HOSTNAME}/configuration.nix"
echo ""
echo "The host has been automatically added to the flake configuration."
echo ""
echo "To deploy to this host, ensure it's configured in leaf-config.nix:"
echo ""
echo "  deployment = {"
echo "    primary = {"
echo "      hostname = \"${HOSTNAME}\";"
echo "      ip = \"<IP_ADDRESS>\";"
echo "    };"
echo "  };"
echo ""
echo "Or add it as a secondary:"
echo ""
echo "  deployment.secondaries = ["
echo "    { hostname = \"${HOSTNAME}\"; ip = \"<IP_ADDRESS>\"; }"
echo "  ];"
echo ""

# Store metadata
cat > "hosts/${HOSTNAME}/metadata.json" << EOF
{
  "hostname": "${HOSTNAME}",
  "serial": "${SERIAL}",
  "model": "${MODEL}",
  "system": "${NIX_SYSTEM}",
  "memory_gb": ${MEMORY_GB},
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "inventory_file": "${INVENTORY_FILE}"
}
EOF

echo "Metadata saved to: hosts/${HOSTNAME}/metadata.json"