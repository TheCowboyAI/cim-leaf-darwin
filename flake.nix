{
  description = "cim-leaf-darwin - Remote deployable CIM leaf node for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, deploy-rs, ... }:
    let
      # Import configurations
      leafConfig = import ./leaf-config.nix { lib = nixpkgs.lib; };
      topologyConfig = import ./topology.nix { lib = nixpkgs.lib; };
      
      # Function to create a Darwin configuration for a specific host
      mkDarwinConfig = { hostname, system ? "aarch64-darwin", username ? "admin" }:
        let
          # Use Nix config as source of truth
          nixLeafConfig = leafConfig;
          
          # Domain module based on config
          domainName = nixLeafConfig.leaf.domain;
          domainModule = ./modules/domains/${domainName}.nix;
          
          # Hardware configuration from inventory (if exists)
          hardwareConfig = ./inventory/${hostname}/hardware.nix;
          hasHardwareConfig = builtins.pathExists hardwareConfig;
          
          # Host-specific configuration (if exists)
          hostConfig = ./hosts/${hostname}/configuration.nix;
          hasHostConfig = builtins.pathExists hostConfig;
          
          # Find hub for this leaf from topology
          leafName = nixLeafConfig.leaf.name;
          leafTopology = topologyConfig.leafs.${leafName} or null;
          hubConfig = if leafTopology != null 
            then topologyConfig.hubs.${leafTopology.hub} or null
            else null;
        in
        darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { 
            inherit inputs hostname username;
            leafConfig = nixLeafConfig;
            topologyConfig = topologyConfig;
            hubConfig = hubConfig;
          };
          modules = [
            ./darwin.nix
            ./modules/nats.nix
            ./modules/monitoring.nix
            ./modules/security.nix
            home-manager.darwinModules.home-manager
            {
              networking.hostName = hostname;
              
              users.users.${username} = {
                home = "/Users/${username}";
              };
              
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./home.nix;
                extraSpecialArgs = { inherit hostname leafConfig; };
              };
            }
          ] 
          ++ nixpkgs.lib.optional (builtins.pathExists domainModule) domainModule
          ++ nixpkgs.lib.optional hasHardwareConfig hardwareConfig
          ++ nixpkgs.lib.optional hasHostConfig hostConfig;
        };
      
      # Load inventory files to generate configurations
      loadInventory = hostname: 
        let
          inventoryPath = ./inventory/${hostname}/latest.json;
        in
          if builtins.pathExists inventoryPath
          then builtins.fromJSON (builtins.readFile inventoryPath)
          else null;
    in
    {
      # Darwin configurations for each host in inventory
      darwinConfigurations = 
        let
          # Default configuration
          defaultConfig = {
            default = mkDarwinConfig {
              hostname = "cim-leaf-darwin";
              username = builtins.getEnv "USER";
            };
          };
          
          # Auto-generate configurations for all inventoried hosts
          inventoryHosts = 
            let
              inventoryDir = ./inventory;
              hasInventory = builtins.pathExists inventoryDir;
              hostDirs = if hasInventory 
                then builtins.attrNames (builtins.readDir inventoryDir)
                else [];
              
              # Filter to only directories that have hardware.nix
              validHosts = builtins.filter (host: 
                builtins.pathExists (inventoryDir + "/${host}/hardware.nix")
              ) hostDirs;
            in
              builtins.listToAttrs (map (host: {
                name = host;
                value = mkDarwinConfig {
                  hostname = host;
                  username = leafConfig.deployment.primary.username or "admin";
                };
              }) validHosts);
        in
          defaultConfig // inventoryHosts;
      
      # Deploy-rs configuration for remote deployment
      deploy = {
        sshUser = "admin";
        sshOpts = [ "-o" "StrictHostKeyChecking=no" ];
        
        nodes = 
          let
            # Auto-generate deploy nodes from leaf configuration
            primaryNode = 
              let
                primary = leafConfig.deployment.primary;
              in
                if primary.hostname != null && primary.ip != null
                then {
                  "${primary.hostname}" = {
                    hostname = primary.ip;
                    profiles.system = {
                      user = "root";
                      path = deploy-rs.lib.aarch64-darwin.activate.darwin 
                        self.darwinConfigurations.${primary.hostname};
                    };
                  };
                }
                else {};
            
            # Secondary nodes
            secondaryNodes = 
              let
                secondaries = leafConfig.deployment.secondaries or [];
              in
                builtins.listToAttrs (map (secondary: {
                  name = secondary.hostname;
                  value = {
                    hostname = secondary.ip;
                    profiles.system = {
                      user = "root";
                      path = deploy-rs.lib.aarch64-darwin.activate.darwin 
                        self.darwinConfigurations.${secondary.hostname};
                    };
                  };
                }) (builtins.filter (s: s.hostname != null && s.ip != null) secondaries));
          in
            primaryNode // secondaryNodes;
      };
      
      # Utility functions
      lib = {
        inherit mkDarwinConfig loadInventory;
        
        # Generate a deploy node from inventory
        mkDeployNode = hostname: ip: {
          hostname = ip;
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.aarch64-darwin.activate.darwin 
              self.darwinConfigurations.${hostname};
          };
        };
      };
      
      # Scripts for deployment workflow
      apps = nixpkgs.lib.genAttrs [ "x86_64-darwin" "aarch64-darwin" ] (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          # Extract inventory from remote host
          extract-inventory = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "extract-inventory" ''
              ${builtins.readFile ./scripts/extract_inventory.sh}
            ''}/bin/extract-inventory";
          };
          
          # Generate configuration from inventory
          generate-config = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "generate-config" ''
              ${builtins.readFile ./scripts/generate_config.sh}
            ''}/bin/generate-config";
          };
          
          # Deploy to remote host
          deploy-host = {
            type = "app";
            program = "${pkgs.writeShellScriptBin "deploy-host" ''
              ${builtins.readFile ./scripts/deploy_host.sh}
            ''}/bin/deploy-host";
          };
        });
    };
}