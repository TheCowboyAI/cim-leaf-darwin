# Production Trading Leaf in Tokyo
# Example configuration for a production trading leaf
{ lib, ... }:

{
  # Leaf identity
  leaf = {
    name = "prod-trading-ap-northeast-1";
    description = "Production trading leaf in Tokyo datacenter";
    domain = "trading";
    region = "ap-northeast-1";
    environment = "prod";
  };

  # Domain configuration
  cim-domain = {
    repository = "https://github.com/TheCowboyAI/cim-domain-trading.git";
    branch = "main";
    modules = [ "core" "events" "commands" "projections" "rules" ];
  };

  # NATS configuration
  nats = {
    cluster = {
      name = "cim-prod";
      id = "PROD-TRADING-TOKYO-01";
    };

    # Connect to Tokyo hub
    leafNode = {
      remotes = [
        {
          url = "nats://hub-ap-northeast-1a.cim.internal:4222";
          credentials = "/etc/cim/creds/prod-trading-tokyo.creds";
        }
        {
          url = "nats://hub-ap-northeast-1b.cim.internal:4222";
          credentials = "/etc/cim/creds/prod-trading-tokyo.creds";
        }
      ];
    };

    # JetStream configuration for trading
    jetstream = {
      domain = "TRADING";
      maxMemoryStore = "16GB"; # High memory for order book
      maxFileStore = "500GB"; # Large storage for trade history
      
      streams = {
        TRADING_EVENTS = {
          subjects = [ "cim.trading.events.>" ];
          retention = "limits";
          maxAge = "90d"; # Regulatory requirement
          maxBytes = "200GB";
          storage = "file";
          replicas = 1;
        };
        
        TRADING_COMMANDS = {
          subjects = [ "cim.trading.commands.>" ];
          retention = "workqueue";
          maxAge = "5m"; # Commands expire quickly
          maxBytes = "2GB";
          storage = "memory"; # Fast command processing
          replicas = 1;
        };
        
        TRADING_ORDERS = {
          subjects = [ "cim.trading.orders.>" ];
          retention = "limits";
          maxAge = "7d"; # Keep recent orders
          maxBytes = "50GB";
          storage = "file";
          replicas = 1;
        };
      };
    };

    # Production security
    authorization = {
      users = [
        {
          user = "trading-service";
          permissions = {
            publish = {
              allow = [ 
                "cim.trading.commands.>"
                "cim.trading.events.>"
                "_INBOX.>"
              ];
            };
            subscribe = {
              allow = [ 
                "cim.trading.>"
                "_INBOX.>"
                "$JS.>"
              ];
            };
          };
        }
        {
          user = "risk-monitor";
          permissions = {
            publish = {
              deny = [ ">" ];
            };
            subscribe = {
              allow = [ 
                "cim.trading.events.order.>"
                "cim.trading.events.trade.>"
              ];
            };
          };
        }
      ];
    };
  };

  # Deployment targets
  deployment = {
    primary = {
      hostname = "tky-mac-prod-01";
      ip = "10.4.1.10";
      username = "cimadmin";
      sshPort = 22;
      
      hardware = {
        arch = "aarch64"; # Mac Studio M2 Ultra
        cores = 24;
        memory = 192; # GB
      };
    };

    secondaries = [
      {
        hostname = "tky-mac-prod-02";
        ip = "10.4.1.11";
        username = "cimadmin";
      }
      {
        hostname = "tky-mac-prod-03";
        ip = "10.4.1.12";
        username = "cimadmin";
      }
    ];

    strategy = {
      parallel = false; # Sequential deployment for safety
      healthCheckTimeout = 600; # 10 minutes
      rollbackOnFailure = true;
    };
  };

  # Production monitoring
  monitoring = {
    enable = true;
    
    prometheus = {
      retention = "30d";
      port = 9090;
      
      remoteWrite = [
        {
          url = "https://prometheus-prod.cim.global/api/v1/write";
          basicAuth = {
            username = "prod-trading-tokyo";
            passwordFile = "/etc/cim/secrets/prometheus-password";
          };
        }
      ];
    };
    
    grafana = {
      enable = false; # No local Grafana in prod
    };
    
    alerts = {
      natsDown = {
        enable = true;
        duration = "2m"; # Quick alerting
      };
      diskSpace = {
        enable = true;
        threshold = 85;
      };
      memoryPressure = {
        enable = true;
        threshold = 80;
      };
      orderLatency = {
        enable = true;
        threshold = "50ms"; # Trading SLA
      };
    };
  };

  # Production backup
  backup = {
    enable = true;
    
    schedule = {
      full = "daily";
      incremental = "hourly";
    };
    
    retention = {
      daily = 14;
      weekly = 8;
      monthly = 12;
    };
    
    destinations = [
      {
        type = "local";
        path = "/backup/cim-leaf";
      }
      {
        type = "s3";
        bucket = "cim-backups-ap-northeast-1";
        prefix = "leafs/prod-trading-tokyo";
        region = "ap-northeast-1";
      }
    ];
  };

  # Production security
  security = {
    firewall = {
      enable = true;
      
      allowedTCPPorts = [
        22    # SSH
        4222  # NATS
        8222  # NATS monitoring
        9090  # Prometheus
        9100  # Node exporter
      ];
      
      natsAllowedSources = [
        "10.4.0.0/16"  # Tokyo datacenter
        "10.1.0.0/16"  # US East (for DR)
      ];
    };
    
    ssh = {
      passwordAuthentication = false;
      permitRootLogin = "no";
      authorizedKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..." # Operations team
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD..." # SRE team
      ];
    };
    
    tls = {
      enable = true;
      
      certificates = {
        ca = "/etc/cim/certs/ca.crt";
        cert = "/etc/cim/certs/prod-trading-tokyo.crt";
        key = "/etc/cim/certs/prod-trading-tokyo.key";
      };
    };
  };

  # Performance tuning for trading
  features = {
    experimental = {
      distributedTracing = true; # Important for latency tracking
      webAssemblyFilters = false;
    };
    
    performance = {
      natsMaxPayload = "1MB"; # Smaller for trading messages
      natsMaxConnections = 5000; # High connection count
      natsMaxPending = "512MB"; # Large pending for bursts
    };
  };
}