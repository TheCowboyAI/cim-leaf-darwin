#!/usr/bin/env bash
# Deploy nix-darwin configuration to remote Mac (nixos-anywhere style)

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <hostname> <ip_address> [username]"
    echo "Example: $0 mac-studio-1 192.168.1.100 admin"
    exit 1
fi

HOSTNAME="$1"
IP_ADDRESS="$2"
USERNAME="${3:-admin}"
SSH_TARGET="${USERNAME}@${IP_ADDRESS}"

echo "=== CIM Leaf Darwin Remote Deployment ==="
echo "Target: ${HOSTNAME} (${SSH_TARGET})"
echo ""

# Check if inventory exists
if [ ! -f "inventory/${HOSTNAME}/latest.json" ]; then
    echo "❌ No inventory found for ${HOSTNAME}"
    echo "   Run first: ./scripts/extract_inventory.sh ${IP_ADDRESS} ${USERNAME}"
    exit 1
fi

# Check if host configuration exists
if [ ! -f "hosts/${HOSTNAME}/configuration.nix" ]; then
    echo "❌ No configuration found for ${HOSTNAME}"
    echo "   Run first: ./scripts/generate_config.sh ${HOSTNAME}"
    exit 1
fi

echo "✓ Found inventory and configuration for ${HOSTNAME}"
echo ""

# Phase 1: Install Nix on remote if needed
echo "Phase 1: Checking Nix installation..."
if ! ssh "${SSH_TARGET}" "command -v nix" &>/dev/null; then
    echo "Installing Nix on remote host..."
    ssh "${SSH_TARGET}" "sh <(curl -L https://nixos.org/nix/install) --daemon --yes"
    echo "✓ Nix installed"
else
    echo "✓ Nix already installed"
fi

# Phase 2: Install nix-darwin on remote if needed
echo ""
echo "Phase 2: Checking nix-darwin..."
if ! ssh "${SSH_TARGET}" "command -v darwin-rebuild" &>/dev/null; then
    echo "Installing nix-darwin on remote host..."
    
    # Create temporary installation flake on remote
    ssh "${SSH_TARGET}" 'cat > /tmp/install-darwin.nix' << 'EOF'
{
  description = "Bootstrap nix-darwin";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs@{ nixpkgs, darwin, ... }: {
    darwinConfigurations."bootstrap" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [ 
        ({ pkgs, ... }: {
          services.nix-daemon.enable = true;
          nix.settings.experimental-features = "nix-command flakes";
          programs.zsh.enable = true;
          system.stateVersion = 4;
        })
      ];
    };
  };
}
EOF
    
    ssh "${SSH_TARGET}" 'cd /tmp && nix run nix-darwin -- switch --flake /tmp/install-darwin.nix#bootstrap'
    echo "✓ nix-darwin installed"
else
    echo "✓ nix-darwin already installed"
fi

# Phase 3: Copy configuration to remote
echo ""
echo "Phase 3: Copying configuration..."
REMOTE_DIR="/tmp/cim-leaf-deploy-${HOSTNAME}"
ssh "${SSH_TARGET}" "mkdir -p ${REMOTE_DIR}"

# Create a deployment flake that includes our configuration
cat > /tmp/deploy-flake.nix << EOF
{
  description = "Deployment flake for ${HOSTNAME}";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  
  outputs = inputs @ { self, nixpkgs, darwin, home-manager, ... }: {
    darwinConfigurations."${HOSTNAME}" = darwin.lib.darwinSystem {
      system = "$(jq -r '.system' "hosts/${HOSTNAME}/metadata.json")";
      modules = [
        ./darwin.nix
        ./modules/nats.nix
        ./hosts/${HOSTNAME}/configuration.nix
        home-manager.darwinModules.home-manager
        {
          users.users.${USERNAME} = {
            home = "/Users/${USERNAME}";
          };
          
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.${USERNAME} = import ./home.nix;
          };
        }
      ];
    };
  };
}
EOF

# Copy all necessary files
echo "Copying files to remote..."
scp -r darwin.nix home.nix modules hosts/${HOSTNAME} /tmp/deploy-flake.nix "${SSH_TARGET}:${REMOTE_DIR}/"

# Phase 4: Build and switch
echo ""
echo "Phase 4: Building and activating configuration..."
ssh "${SSH_TARGET}" "cd ${REMOTE_DIR} && mv deploy-flake.nix flake.nix && darwin-rebuild switch --flake .#${HOSTNAME}"

# Phase 5: Verify deployment
echo ""
echo "Phase 5: Verifying deployment..."
echo "Checking NATS service..."
if ssh "${SSH_TARGET}" "curl -s http://localhost:8222/healthz" &>/dev/null; then
    echo "✓ NATS is running"
else
    echo "⚠️  NATS health check failed"
fi

# Cleanup
ssh "${SSH_TARGET}" "rm -rf ${REMOTE_DIR}"
rm -f /tmp/deploy-flake.nix

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Host ${HOSTNAME} is now configured as a CIM leaf node!"
echo ""
echo "Useful commands:"
echo "  Check NATS status:  ssh ${SSH_TARGET} 'curl http://localhost:8222/varz | jq'"
echo "  View NATS logs:     ssh ${SSH_TARGET} 'tail -f /var/log/nats/*.log'"
echo "  Rebuild remotely:   ssh ${SSH_TARGET} 'darwin-rebuild switch'"