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

# Create host-specific configuration
mkdir -p "hosts/${HOSTNAME}"

cat > "hosts/${HOSTNAME}/configuration.nix" << EOF
# Auto-generated configuration for ${HOSTNAME}
# Serial: ${SERIAL}
# Model: ${MODEL}
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

{ config, pkgs, lib, ... }:

{
  # Host-specific settings
  networking.hostName = "${HOSTNAME}";
  
  # Hardware-specific optimizations
  nix.settings = {
    # Adjust based on available memory
    max-jobs = $(( MEMORY_GB > 16 ? 8 : 4 ));
    cores = 0; # Use all available cores
  };
  
  # NATS configuration specific to this host
  launchd.daemons.nats.config.ProgramArguments = lib.mkForce [
    "\${pkgs.nats-server}/bin/nats-server"
    "-js"
    "-sd" "/var/lib/nats/jetstream"
    "-m" "8222"
    "-p" "4222"
    "--name" "${HOSTNAME}"
    "--max_payload" "8MB"
    "--max_connections" "1000"
    # Adjust memory based on available RAM
    "--max_memory_store" "${MEMORY_GB > 32 ? "4GB" : "2GB"}"
    "--max_file_store" "${MEMORY_GB > 32 ? "100GB" : "50GB"}"
  ];
}
EOF

# Update flake.nix to include this host
echo ""
echo "Host configuration generated at: hosts/${HOSTNAME}/configuration.nix"
echo ""
echo "To add this host to flake.nix, add the following to darwinConfigurations:"
echo ""
echo "  \"${HOSTNAME}\" = mkDarwinConfig {"
echo "    hostname = \"${HOSTNAME}\";"
echo "    system = \"${NIX_SYSTEM}\";"
echo "  };"
echo ""
echo "And to deploy.nodes:"
echo ""
echo "  \"${HOSTNAME}\" = {"
echo "    hostname = \"<IP_ADDRESS>\";"
echo "    profiles.system = {"
echo "      user = \"root\";"
echo "      path = deploy-rs.lib.${NIX_SYSTEM}.activate.darwin self.darwinConfigurations.\"${HOSTNAME}\";"
echo "    };"
echo "  };"
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