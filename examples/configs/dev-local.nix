# Local Development Configuration
# Example for developers running CIM locally
{ lib, ... }:

{
  # Leaf identity
  leaf = {
    name = "dev-local-${builtins.getEnv "USER"}";
    description = "Local development environment";
    domain = "trading"; # Change to your domain
    region = "us-east-1"; # Default region for dev
    environment = "dev";
  };

  # Domain configuration
  cim-domain = {
    repository = "https://github.com/TheCowboyAI/cim-domain-trading.git";
    branch = "develop"; # Dev branch
    modules = [ "core" "events" "commands" "projections" ];
  };

  # NATS configuration - local instance
  nats = {
    cluster = {
      name = "cim-dev";
      id = lib.mkDefault null; # Auto-generate
    };

    # No leaf node for local dev - run standalone
    leafNode = {
      remotes = [];
    };

    # Minimal JetStream for development
    jetstream = {
      domain = "DEV_LOCAL";
      maxMemoryStore = "1GB";
      maxFileStore = "10GB";
      
      streams = {
        DEV_EVENTS = {
          subjects = [ "cim.>.events.>" ];
          retention = "limits";
          maxAge = "1d"; # Short retention for dev
          maxBytes = "1GB";
          storage = "file";
          replicas = 1;
        };
        
        DEV_COMMANDS = {
          subjects = [ "cim.>.commands.>" ];
          retention = "workqueue";
          maxAge = "1h";
          maxBytes = "100MB";
          storage = "memory";
          replicas = 1;
        };
      };
    };

    # Simple dev authentication
    authorization = {
      users = [
        {
          user = "dev";
          permissions = {
            publish = {
              allow = [ ">" ]; # Allow all in dev
            };
            subscribe = {
              allow = [ ">" ]; # Allow all in dev
            };
          };
        }
      ];
    };
  };

  # Local deployment only
  deployment = {
    primary = {
      hostname = "localhost";
      ip = "127.0.0.1";
      username = builtins.getEnv "USER";
      sshPort = 22;
      
      hardware = {
        arch = lib.mkDefault null; # Auto-detect
        cores = lib.mkDefault null;
        memory = lib.mkDefault null;
      };
    };

    secondaries = []; # No secondaries for dev

    strategy = {
      parallel = false;
      healthCheckTimeout = 60;
      rollbackOnFailure = false; # Don't rollback in dev
    };
  };

  # Full monitoring in dev for testing
  monitoring = {
    enable = true;
    
    prometheus = {
      retention = "7d";
      port = 9090;
      remoteWrite = []; # No remote write in dev
    };
    
    grafana = {
      enable = true; # Enable for local dashboards
      port = 3000;
      adminPasswordFile = null; # Use default admin/admin
    };
    
    alerts = {
      natsDown = {
        enable = false; # No alerts in dev
      };
      diskSpace = {
        enable = true;
        threshold = 95; # Higher threshold for dev
      };
      memoryPressure = {
        enable = true;
        threshold = 90;
      };
    };
  };

  # Minimal backup for dev
  backup = {
    enable = false; # Usually not needed for dev
    
    schedule = {
      full = "never";
      incremental = "never";
    };
    
    destinations = [
      {
        type = "local";
        path = "/tmp/cim-backups";
      }
    ];
  };

  # Relaxed security for development
  security = {
    firewall = {
      enable = false; # No firewall for dev
      
      allowedTCPPorts = [
        22    # SSH
        4222  # NATS
        8222  # NATS monitoring
        9090  # Prometheus
        9100  # Node exporter
        3000  # Grafana
      ];
    };
    
    ssh = {
      passwordAuthentication = true; # Allow password in dev
      permitRootLogin = "yes"; # Allow root for debugging
      authorizedKeys = [];
    };
    
    tls = {
      enable = false; # No TLS in dev
      certificates = {
        ca = null;
        cert = null;
        key = null;
      };
    };
  };

  # Dev features
  features = {
    experimental = {
      distributedTracing = true; # Test new features
      webAssemblyFilters = true; # Test WASM filters
    };
    
    performance = {
      natsMaxPayload = "16MB"; # Larger for testing
      natsMaxConnections = 100; # Lower for dev
      natsMaxPending = "64MB";
    };
  };
}