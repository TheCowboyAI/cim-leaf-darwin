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
          ] ++ nixpkgs.lib.optional (builtins.pathExists domainModule) domainModule;
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
      darwinConfigurations = {
        # Default configuration for manual setup
        default = mkDarwinConfig {
          hostname = "cim-leaf-darwin";
          username = builtins.getEnv "USER";
        };
        
        # Example: Add specific hosts as they're inventoried
        # "mac-studio-1" = mkDarwinConfig {
        #   hostname = "mac-studio-1";
        #   username = "admin";
        # };
      };
      
      # Deploy-rs configuration for remote deployment
      deploy = {
        sshUser = "admin";
        sshOpts = [ "-o" "StrictHostKeyChecking=no" ];
        
        nodes = {
          # Nodes will be added dynamically based on inventory
          # Example:
          # "mac-studio-1" = {
          #   hostname = "192.168.1.100";
          #   profiles.system = {
          #     user = "root";
          #     path = deploy-rs.lib.aarch64-darwin.activate.darwin self.darwinConfigurations."mac-studio-1";
          #   };
          # };
        };
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