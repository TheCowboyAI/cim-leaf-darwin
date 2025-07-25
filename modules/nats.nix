{ config, lib, pkgs, hostname, leafConfig, ... }:

let
  cfg = if leafConfig != null then leafConfig else {
    leaf = { name = hostname; domain = "default"; };
    nats = {
      cluster_name = "cim-cluster";
      jetstream = {
        max_memory_store = "4GB";
        max_file_store = "100GB";
      };
      leaf_connections = [];
    };
  };
in
{
  # NATS launchd service
  launchd.daemons.nats = {
    enable = true;
    config = {
      Label = "org.nats.server";
      ProgramArguments = [
        "${pkgs.nats-server}/bin/nats-server"
        "-js"                           # Enable JetStream
        "-sd" "/var/lib/nats/jetstream" # Storage directory
        "-m" "8222"                     # Monitoring port
        "-p" "4222"                     # Client port
        "--name" cfg.leaf.name          # Use leaf name as server name
        "--max_payload" "8MB"
        "--max_connections" "1000"
        "--cluster_name" cfg.nats.cluster_name
        "--js_domain" cfg.leaf.domain
      ] ++ lib.optionals (cfg.nats.leaf_connections != []) (
        lib.flatten (map (conn: [
          "--routes" conn.url
        ]) cfg.nats.leaf_connections)
      );
      KeepAlive = true;
      RunAtLoad = true;
      StandardErrorPath = "/var/log/nats/error.log";
      StandardOutPath = "/var/log/nats/output.log";
      WorkingDirectory = "/var/lib/nats";
    };
  };
  
  # Create NATS directories with proper permissions
  system.activationScripts.nats = {
    text = ''
      echo "Setting up NATS directories..."
      mkdir -p /var/lib/nats/jetstream
      mkdir -p /var/log/nats
      chmod 755 /var/lib/nats
      chmod 755 /var/log/nats
      
      # If running as specific user (future enhancement)
      # chown -R nats:nats /var/lib/nats
      # chown -R nats:nats /var/log/nats
    '';
  };
  
  # Add NATS tools to system packages
  environment.systemPackages = with pkgs; [
    nats-server
    natscli
  ];
  
  # Environment variables for NATS
  environment.variables = {
    NATS_URL = "nats://localhost:4222";
  };
  
  # Firewall rules (if firewall is enabled)
  # networking.firewall.allowedTCPPorts = [ 4222 8222 ];
}