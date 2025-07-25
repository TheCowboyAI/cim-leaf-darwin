# Deterministic leaf configuration
# This file defines all configuration for a CIM leaf node
{ lib, ... }:

{
  # Leaf identity
  leaf = {
    name = "LEAF_NAME"; # e.g., "tokyo-prod-1"
    description = "LEAF_DESCRIPTION"; # e.g., "Production trading leaf in Tokyo"
    domain = "DOMAIN_NAME"; # e.g., "trading"
    region = "REGION_CODE"; # e.g., "ap-northeast-1"
    environment = "ENVIRONMENT"; # e.g., "prod", "staging", "dev"
  };

  # Domain configuration
  cim-domain = {
    repository = "https://github.com/YOUR_ORG/cim-domain-DOMAIN_NAME.git";
    branch = "main";
    modules = [ "core" "events" "commands" "projections" ];
  };

  # NATS configuration
  nats = {
    cluster = {
      name = "CLUSTER_NAME"; # e.g., "cim-prod"
      id = lib.mkDefault null; # Auto-generated if null
    };

    # Leaf node connections
    leafNode = {
      remotes = [
        {
          url = "nats://UPSTREAM_HOST:4222";
          credentials = null; # Path to credentials file
        }
      ];
    };

    # JetStream configuration
    jetstream = {
      domain = lib.mkDefault "DOMAIN_NAME";
      maxMemoryStore = "4GB";
      maxFileStore = "100GB";
      
      # Streams to create
      streams = {
        "${lib.toUpper "DOMAIN_NAME"}_EVENTS" = {
          subjects = [ "cim.DOMAIN_NAME.events.>" ];
          retention = "limits";
          maxAge = "30d";
          maxBytes = "10GB";
          storage = "file";
          replicas = 1;
        };
        
        "${lib.toUpper "DOMAIN_NAME"}_COMMANDS" = {
          subjects = [ "cim.DOMAIN_NAME.commands.>" ];
          retention = "workqueue";
          maxAge = "1h";
          maxBytes = "1GB";
          storage = "file";
          replicas = 1;
        };
      };
    };

    # Security
    authorization = {
      users = [
        {
          user = "service";
          permissions = {
            publish = {
              allow = [ "cim.DOMAIN_NAME.>" ];
            };
            subscribe = {
              allow = [ "cim.DOMAIN_NAME.>" "_INBOX.>" ];
            };
          };
        }
        {
          user = "monitor";
          permissions = {
            publish = {
              deny = [ ">" ];
            };
            subscribe = {
              allow = [ "$SYS.>" ];
            };
          };
        }
      ];
    };
  };

  # Deployment targets
  deployment = {
    # Primary host (required)
    primary = {
      hostname = "HOST_NAME"; # e.g., "mac-studio-1"
      ip = "HOST_IP"; # e.g., "192.168.1.100"
      username = lib.mkDefault "admin";
      sshPort = lib.mkDefault 22;
      
      # Hardware hints for optimization
      hardware = {
        arch = lib.mkDefault "aarch64"; # or "x86_64"
        cores = lib.mkDefault null; # Auto-detect if null
        memory = lib.mkDefault null; # Auto-detect if null
      };
    };

    # Secondary hosts (optional)
    secondaries = [
      # {
      #   hostname = "mac-studio-2";
      #   ip = "192.168.1.101";
      #   username = "admin";
      # }
    ];

    # Deployment strategy
    strategy = {
      parallel = false; # Deploy to all hosts in parallel
      healthCheckTimeout = 300; # Seconds to wait for health check
      rollbackOnFailure = true;
    };
  };

  # Monitoring configuration
  monitoring = {
    enable = lib.mkDefault true;
    
    prometheus = {
      retention = "15d";
      port = 9090;
      
      # Remote write for centralized metrics
      remoteWrite = [
        # {
        #   url = "https://prometheus.example.com/api/v1/write";
        #   basicAuth = {
        #     username = "leaf";
        #     passwordFile = "/run/secrets/prometheus-password";
        #   };
        # }
      ];
    };
    
    grafana = {
      enable = lib.mkDefault (leaf.environment != "prod");
      port = 3000;
      adminPasswordFile = null; # Use default if null
    };
    
    # Alerting rules
    alerts = {
      natsDown = {
        enable = true;
        duration = "5m";
      };
      diskSpace = {
        enable = true;
        threshold = 90; # Percentage
      };
      memoryPressure = {
        enable = true;
        threshold = 85; # Percentage
      };
    };
  };

  # Backup configuration
  backup = {
    enable = lib.mkDefault true;
    
    schedule = {
      full = "daily"; # daily, weekly, monthly
      incremental = "hourly"; # hourly, daily, never
    };
    
    retention = {
      daily = 7;
      weekly = 4;
      monthly = 3;
    };
    
    destinations = [
      {
        type = "local";
        path = "/var/backups/cim-leaf";
      }
      # {
      #   type = "s3";
      #   bucket = "cim-backups";
      #   prefix = "leafs/${leaf.name}";
      #   region = "us-east-1";
      # }
    ];
  };

  # Security settings
  security = {
    firewall = {
      enable = lib.mkDefault true;
      
      allowedTCPPorts = [
        22    # SSH
        4222  # NATS
        8222  # NATS monitoring
        9090  # Prometheus
        9100  # Node exporter
      ] ++ lib.optional monitoring.grafana.enable monitoring.grafana.port;
      
      # Restrict NATS to specific sources
      natsAllowedSources = [
        # "192.168.1.0/24"
        # "10.0.0.0/8"
      ];
    };
    
    ssh = {
      passwordAuthentication = false;
      permitRootLogin = "no";
      authorizedKeys = [
        # "ssh-rsa AAAAB3..."
      ];
    };
    
    # TLS configuration
    tls = {
      enable = lib.mkDefault (leaf.environment == "prod");
      
      # Paths to certificates
      certificates = {
        ca = null; # "/etc/cim/certs/ca.crt"
        cert = null; # "/etc/cim/certs/leaf.crt"
        key = null; # "/etc/cim/certs/leaf.key"
      };
    };
  };

  # Feature flags
  features = {
    # Enable experimental features
    experimental = {
      distributedTracing = false;
      webAssemblyFilters = false;
    };
    
    # Performance tuning
    performance = {
      natsMaxPayload = "8MB";
      natsMaxConnections = 1000;
      natsMaxPending = "256MB";
    };
  };
}