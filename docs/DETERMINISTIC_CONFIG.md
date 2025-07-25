# Deterministic Configuration Guide

This guide explains how to configure CIM Leaf Darwin using deterministic Nix configuration instead of interactive prompts.

## Overview

CIM Leaf Darwin uses Nix as the source of truth for all configuration. This ensures:
- Reproducible deployments
- Version-controlled configuration
- Type-safe settings
- Declarative system state

## Configuration Files

### 1. `leaf-config.nix` - Leaf Configuration

This is the main configuration file for your leaf node. It contains all settings specific to your deployment.

```nix
{
  # Leaf identity
  leaf = {
    name = "prod-trading-tokyo";
    description = "Production trading leaf in Tokyo";
    domain = "trading";
    region = "ap-northeast-1";
    environment = "prod";
  };

  # NATS messaging configuration
  nats = {
    cluster = {
      name = "cim-prod";
      id = "PROD-TRADING-TOKYO-01";
    };
    
    leafNode = {
      remotes = [{
        url = "nats://hub.cim.internal:4222";
        credentials = "/etc/cim/creds/leaf.creds";
      }];
    };
  };

  # Deployment targets
  deployment = {
    primary = {
      hostname = "mac-prod-01";
      ip = "10.1.1.10";
      username = "cimadmin";
    };
    secondaries = [
      { hostname = "mac-prod-02"; ip = "10.1.1.11"; }
    ];
  };
}
```

### 2. `topology.nix` - Network Topology

Defines the global CIM network structure:

```nix
{
  # Geographic regions
  regions = {
    "us-east-1" = {
      name = "US East (Virginia)";
      timezone = "America/New_York";
      primary = true;
    };
  };

  # Hub nodes (NATS super-clusters)
  hubs = {
    "hub-us-east-1" = {
      region = "us-east-1";
      endpoints = [
        "nats://hub-us-east-1.cim.internal:4222"
      ];
    };
  };

  # Domain definitions
  domains = {
    trading = {
      description = "Real-time trading";
      primaryRegion = "us-east-1";
    };
  };

  # Leaf assignments
  leafs = {
    "prod-trading-tokyo" = {
      domain = "trading";
      environment = "prod";
      region = "ap-northeast-1";
      hub = "hub-ap-northeast-1";
    };
  };
}
```

## Configuration Sections

### Leaf Identity

```nix
leaf = {
  name = "unique-leaf-name";        # Globally unique identifier
  description = "Human description"; # What this leaf does
  domain = "domain-name";           # Business domain (trading, analytics, etc.)
  region = "region-code";           # AWS-style region code
  environment = "env";              # dev, staging, or prod
};
```

### NATS Configuration

```nix
nats = {
  cluster = {
    name = "cluster-name";          # Cluster this leaf belongs to
    id = "UNIQUE-ID";              # Optional unique cluster ID
  };

  leafNode = {
    remotes = [                     # Hub connections
      {
        url = "nats://host:4222";
        credentials = "/path/to/creds";
      }
    ];
  };

  jetstream = {
    domain = "DOMAIN";             # JetStream domain
    maxMemoryStore = "16GB";       # Memory for streams
    maxFileStore = "500GB";        # Disk for streams
    
    streams = {                    # Stream definitions
      EVENTS = {
        subjects = [ "cim.events.>" ];
        retention = "limits";
        maxAge = "90d";
      };
    };
  };

  authorization = {                # User permissions
    users = [{
      user = "service-account";
      permissions = {
        publish.allow = [ "cim.>" ];
        subscribe.allow = [ "cim.>" ];
      };
    }];
  };
};
```

### Deployment Configuration

```nix
deployment = {
  primary = {
    hostname = "mac-01";           # Hostname
    ip = "10.1.1.10";             # IP address
    username = "admin";            # SSH username
    sshPort = 22;                  # SSH port
    
    hardware = {                   # Optional hardware hints
      arch = "aarch64";           # Architecture
      cores = 24;                 # CPU cores
      memory = 192;               # RAM in GB
    };
  };

  secondaries = [                  # Additional hosts
    { hostname = "mac-02"; ip = "10.1.1.11"; }
  ];

  strategy = {
    parallel = false;              # Deploy sequentially
    healthCheckTimeout = 600;      # Seconds to wait
    rollbackOnFailure = true;      # Auto-rollback on error
  };
};
```

### Monitoring Configuration

```nix
monitoring = {
  enable = true;
  
  prometheus = {
    retention = "30d";
    port = 9090;
    
    remoteWrite = [{              # Central metrics
      url = "https://prometheus.example.com/write";
      basicAuth = {
        username = "leaf";
        passwordFile = "/etc/secrets/prom-pass";
      };
    }];
  };

  grafana = {
    enable = false;               # Usually disabled in prod
    port = 3000;
  };

  alerts = {
    natsDown.enable = true;
    diskSpace = {
      enable = true;
      threshold = 85;             # Percentage
    };
  };
};
```

### Backup Configuration

```nix
backup = {
  enable = true;
  
  schedule = {
    full = "daily";               # daily, weekly, monthly
    incremental = "hourly";       # hourly, daily
  };

  retention = {
    daily = 14;                   # Keep 14 daily backups
    weekly = 8;                   # Keep 8 weekly backups
    monthly = 12;                 # Keep 12 monthly backups
  };

  destinations = [
    {
      type = "local";
      path = "/backup/cim";
    }
    {
      type = "s3";
      bucket = "cim-backups";
      prefix = "leafs/prod-trading";
      region = "us-east-1";
    }
  ];
};
```

### Security Configuration

```nix
security = {
  firewall = {
    enable = true;
    
    allowedTCPPorts = [
      22    # SSH
      4222  # NATS
      8222  # NATS monitoring
      9090  # Prometheus
    ];

    natsAllowedSources = [
      "10.0.0.0/8"               # Internal networks only
    ];
  };

  ssh = {
    passwordAuthentication = false;
    permitRootLogin = "no";
    authorizedKeys = [
      "ssh-rsa AAAAB3..."        # Admin keys
    ];
  };

  tls = {
    enable = true;
    certificates = {
      ca = "/etc/cim/certs/ca.crt";
      cert = "/etc/cim/certs/leaf.crt";
      key = "/etc/cim/certs/leaf.key";
    };
  };
};
```

## Example Configurations

### Production Trading Leaf

See `examples/configs/prod-trading-tokyo.nix` for a complete production configuration with:
- High-performance settings
- Full security hardening
- Remote monitoring
- S3 backups
- Multiple hosts

### Development Environment

See `examples/configs/dev-local.nix` for a development configuration with:
- Relaxed security
- Local monitoring
- No backups
- Single host

## Migration from Interactive Setup

If you have an existing `leaf.config.json` from the interactive setup:

1. Create `leaf-config.nix` based on the JSON values
2. Add additional configuration sections (monitoring, backup, etc.)
3. Run `./scripts/setup_leaf_deterministic.sh`
4. Verify with `nix flake check`
5. Remove the old `leaf.config.json.template`

## Validation

Always validate your configuration:

```bash
# Check syntax and types
nix flake check

# Evaluate specific values
nix eval --raw --impure --expr '(import ./leaf-config.nix {}).leaf.name'

# Build without deploying
darwin-rebuild build --flake .
```

## Best Practices

1. **Use Version Control**: Commit `leaf-config.nix` to track changes
2. **Separate Secrets**: Use `passwordFile` instead of inline passwords
3. **Test First**: Use `darwin-rebuild build` before `switch`
4. **Document Changes**: Add comments explaining non-obvious settings
5. **Use Examples**: Start from example configs and modify
6. **Validate Network**: Ensure IPs and hostnames are correct
7. **Plan Topology**: Design your network topology before deployment

## Troubleshooting

### "Configuration contains placeholder values"

The setup script checks for placeholder strings like `LEAF_NAME`. Replace all placeholders with actual values.

### "Missing lib reference"

Ensure your configuration starts with:
```nix
{ lib, ... }:
```

### "Attribute not found"

Check spelling and nesting of configuration attributes. Use `nix repl` to explore:
```bash
nix repl
:l ./leaf-config.nix
```

### Network Issues

Verify:
- Hub URLs are reachable
- Credentials files exist
- Firewall rules allow connections
- TLS certificates are valid (if enabled)