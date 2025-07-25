# Inventory Management Guide

This guide explains how CIM Leaf Darwin manages hardware inventory and automatically generates optimized Nix configurations.

## Overview

The inventory system:
1. Extracts detailed hardware information from Mac systems
2. Stores it as both JSON (for queries) and Nix (for configuration)
3. Automatically generates optimized configurations based on hardware
4. Integrates with the flake to enable automatic host discovery

## Workflow

### 1. Extract Inventory from Remote Mac

```bash
./scripts/extract_inventory.sh <ip_address> [username]
```

This creates:
- `inventory/<hostname>/hardware_<timestamp>.json` - Raw inventory data
- `inventory/<hostname>/latest.json` - Symlink to latest
- `inventory/<hostname>/hardware.nix` - Nix configuration
- `hosts/<hostname>/hardware.nix` - Copy for host-specific use

### 2. Generate Host Configuration

```bash
./scripts/generate_config.sh <hostname>
```

This creates:
- `hosts/<hostname>/configuration.nix` - Host-specific overrides
- `hosts/<hostname>/metadata.json` - Generation metadata

### 3. Automatic Flake Integration

The flake.nix automatically:
- Discovers all hosts with `inventory/<hostname>/hardware.nix`
- Creates Darwin configurations for each host
- Configures deploy-rs nodes based on `leaf-config.nix`

## Inventory Structure

### JSON Format

```json
{
  "system_info": {
    "hostname": "mac-studio-1",
    "model": "Mac14,13",
    "serial_number": "XXXXX",
    "architecture": "arm64",
    "macos_version": "14.2.1"
  },
  "hardware": {
    "cpu_type": "Apple M2 Ultra",
    "cpu_cores": 24,
    "memory_gb": 192
  },
  "disks": [...],
  "network_interfaces": [...]
}
```

### Nix Format

```nix
{
  # System identification
  system = {
    hostname = "mac-studio-1";
    model = "Mac14,13";
    serialNumber = "XXXXX";
  };

  # Hardware specifications
  hardware = {
    cpu = {
      type = "Apple M2 Ultra";
      cores = 24;
    };
    memory = {
      sizeGB = 192;
    };
    arch = "arm64";
  };

  # Performance recommendations
  performance = {
    memoryPressure.threshold = 90;
    maxConcurrency = "high";
    nats = {
      maxConnections = 10000;
      maxPending = "2GB";
    };
  };

  # Storage recommendations
  storage = {
    jetstream = {
      maxFileStore = "500GB";
      maxMemoryStore = "16GB";
    };
  };
}
```

## Hardware-Based Optimizations

The system automatically configures based on detected hardware:

### CPU Optimizations
- **16+ cores**: High concurrency, 10000 max connections
- **8-15 cores**: Medium concurrency, 5000 max connections
- **<8 cores**: Low concurrency, 1000 max connections

### Memory Optimizations
- **64GB+**: 16GB JetStream memory, 90% pressure threshold
- **32-63GB**: 8GB JetStream memory, 85% pressure threshold
- **<32GB**: 4GB JetStream memory, 80% pressure threshold

### Storage Optimizations
- **1TB+**: 500GB JetStream storage, 90 day retention
- **500GB-1TB**: 200GB JetStream storage, 30 day retention
- **<500GB**: 100GB JetStream storage, 14 day retention

## Event Tracking

All inventory operations emit events:
- `inventory.extraction.started`
- `inventory.hardware.discovered`
- `inventory.extraction.completed`
- `inventory.extraction.failed`

Query inventory events:
```bash
./scripts/event_query.sh events --type inventory
```

## Multi-Host Management

### Configure Multiple Hosts

In `leaf-config.nix`:

```nix
deployment = {
  primary = {
    hostname = "mac-prod-01";
    ip = "10.1.1.10";
  };
  
  secondaries = [
    { hostname = "mac-prod-02"; ip = "10.1.1.11"; }
    { hostname = "mac-prod-03"; ip = "10.1.1.12"; }
  ];
};
```

### Bulk Inventory Collection

```bash
# Primary
./scripts/extract_inventory.sh 10.1.1.10 admin

# Secondaries
for ip in 10.1.1.11 10.1.1.12; do
  ./scripts/extract_inventory.sh $ip admin
done
```

### Deploy to All Hosts

```bash
# Deploy using nix flake
nix run .#deploy-host mac-prod-01 10.1.1.10
nix run .#deploy-host mac-prod-02 10.1.1.11
nix run .#deploy-host mac-prod-03 10.1.1.12
```

## Inventory Queries

### List All Inventoried Hosts

```bash
ls -la inventory/
```

### Compare Hardware Across Hosts

```bash
for host in inventory/*/latest.json; do
  echo "=== $(basename $(dirname $host)) ==="
  jq -r '.hardware | "CPU: \(.cpu_type), Cores: \(.cpu_cores), RAM: \(.memory_gb)GB"' $host
done
```

### Find Hosts by Criteria

```bash
# Find all hosts with 32GB+ RAM
for host in inventory/*/latest.json; do
  if [ $(jq '.hardware.memory_gb' $host) -ge 32 ]; then
    basename $(dirname $host)
  fi
done
```

## Troubleshooting

### "No inventory found for hostname"

Extract inventory first:
```bash
./scripts/extract_inventory.sh <ip> <user>
```

### Hardware Detection Issues

Check SSH access and run manually:
```bash
ssh user@host 'system_profiler SPHardwareDataType'
```

### Flake Not Finding Hosts

Ensure `inventory/<hostname>/hardware.nix` exists:
```bash
nix flake show
```

### Configuration Not Applied

Verify the host is in `leaf-config.nix`:
```bash
nix eval .#deploy.nodes
```

## Best Practices

1. **Regular Updates**: Re-inventory after hardware changes
2. **Version Control**: Commit inventory files for history
3. **Review Generated Configs**: Check `hosts/*/configuration.nix`
4. **Test Locally**: Use `darwin-rebuild build` before deploying
5. **Monitor Events**: Track inventory operations in event stream