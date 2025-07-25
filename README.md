# CIM Leaf Darwin Template

A GitHub template repository for deploying CIM (Composable Information Machine) leaf nodes on Darwin (macOS) systems using nix-darwin.

## 🚀 Using This Template

### 1. Create Your Leaf Repository

1. Click "Use this template" on GitHub
2. Name your repository: `cim-leaf-[LEAF_NAME]` (e.g., `cim-leaf-tokyo-prod-1`)
3. Clone your new repository

### 2. Configure Your Leaf

This template uses deterministic Nix configuration. Configure your leaf by editing:

1. **`leaf-config.nix`** - Main leaf configuration
   - Replace all placeholders (LEAF_NAME, DOMAIN_NAME, etc.)
   - Set your deployment targets, NATS configuration, monitoring, etc.
   - See `examples/configs/` for reference configurations

2. **`topology.nix`** (optional) - Network topology definition
   - Define regions, hubs, domains, and leaf assignments
   - Configure routing policies and security settings

3. Run the setup script to apply configuration:

```bash
./scripts/setup_leaf_deterministic.sh
```

This will:
- Read configuration from `leaf-config.nix`
- Generate domain modules and JSON configs
- Initialize the event store
- Create initial projections

### 3. Commit Your Configuration

```bash
git add -A
git commit -m "Initialize leaf configuration"
git push
```

## 📦 Domain Integration

Each leaf is associated with a CIM domain that provides:
- Event definitions
- Command handlers
- Projection builders
- Domain-specific logic

### Sync Domain Modules

If your domain repository exists:

```bash
./scripts/sync_domain.sh
```

This pulls the latest domain modules from your configured `cim-domain-[DOMAIN]` repository.

## 📋 Prerequisites

Target Macs must have:
- Command Line Developer Tools: `xcode-select --install`
- SSH enabled (for remote deployment): `sudo systemsetup -setremotelogin on`

## 🖥️ Remote Deployment

### 1. Extract Hardware Inventory

```bash
./scripts/extract_inventory.sh 192.168.1.100 admin
```

Creates `inventory/<hostname>/hardware_TIMESTAMP.json` with complete system information.

### 2. Generate Host Configuration

```bash
./scripts/generate_config.sh mac-studio-1
```

Creates `hosts/mac-studio-1/configuration.nix` optimized for the hardware.

### 3. Deploy to Remote Host

```bash
./scripts/deploy_host.sh mac-studio-1 192.168.1.100 admin
```

This will:
- Install Nix and nix-darwin if needed
- Deploy your leaf configuration
- Start NATS with domain-specific settings
- Connect to upstream NATS cluster

## 🏗️ Architecture

```
cim-leaf-[NAME]/
├── leaf-config.nix        # Deterministic leaf configuration
├── topology.nix           # Network topology definition
├── leaf.config.json       # Auto-generated from Nix
├── modules/
│   ├── nats.nix          # NATS service configuration
│   ├── monitoring.nix    # Prometheus/Grafana setup
│   ├── security.nix      # Security hardening
│   └── domains/          # Domain-specific modules
│       └── [DOMAIN].nix  # Your domain configuration
├── examples/
│   └── configs/          # Example configurations
│       ├── prod-trading-tokyo.nix
│       └── dev-local.nix
├── inventory/            # Hardware inventories
├── hosts/               # Generated host configs
├── events/              # Event stream (append-only)
├── projections/         # Current state from events
└── scripts/             # Deployment automation
```

## 🔧 Leaf Configuration

Configuration is defined in `leaf-config.nix`:

```nix
{
  leaf = {
    name = "tokyo-prod-1";
    domain = "trading";
    region = "ap-northeast-1";
    environment = "prod";
  };
  
  nats = {
    cluster = {
      name = "cim-prod";
      id = "PROD-TRADING-TOKYO-01";
    };
    leafNode = {
      remotes = [{
        url = "nats://hub-ap-northeast-1.cim.internal:4222";
        credentials = "/etc/cim/creds/prod-trading-tokyo.creds";
      }];
    };
  };
  
  deployment = {
    primary = {
      hostname = "tky-mac-prod-01";
      ip = "10.4.1.10";
    };
    secondaries = [
      { hostname = "tky-mac-prod-02"; ip = "10.4.1.11"; }
    ];
  };
}
```

The JSON file `leaf.config.json` is auto-generated from the Nix configuration.

## 🌐 Multi-Host Deployment

Configure multiple hosts in `leaf-config.nix`:

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

Then deploy to each host:

1. Extract inventory: `./scripts/extract_inventory.sh <ip> <user>`
2. Deploy primary: `./scripts/deploy_host.sh <primary-host> <primary-ip>`
3. Deploy secondaries: `./scripts/deploy_host.sh <host> <ip>`

## 🔄 Updating

To update a deployed leaf:

```bash
# Pull latest changes
git pull

# Sync domain updates
./scripts/sync_domain.sh

# Redeploy to host
./scripts/deploy_host.sh mac-studio-1 192.168.1.100
```

## 📚 Development

Follow CIM principles:
- Event-driven architecture (no CRUD)
- CQRS pattern
- Domain-driven design
- Test-driven development

See `.claude/` for detailed development guidelines.

## 🤝 Creating a Domain Repository

Domain repositories (`cim-domain-[NAME]`) should provide:

```
cim-domain-[NAME]/
├── modules/
│   ├── events.nix       # Event definitions
│   ├── commands.nix     # Command handlers
│   └── projections.nix  # Read models
├── leaf-configs/        # Leaf-specific overrides
└── README.md
```

## 🔧 Operations

### Health Monitoring
```bash
# Run health check
./scripts/health_check.sh

# View system status
./scripts/maintenance.sh status

# Monitor metrics (non-prod)
open http://localhost:3000  # Grafana dashboard
```

### Backup & Recovery
```bash
# Create backup
./scripts/backup_restore.sh backup

# List backups
./scripts/backup_restore.sh list

# Restore from backup
./scripts/backup_restore.sh restore 20240124_120000
```

### Maintenance
```bash
# Update system
./scripts/maintenance.sh update

# Clean old data
./scripts/maintenance.sh cleanup

# Compact JetStream
./scripts/maintenance.sh compact
```

## 🔒 Security Features

- **Environment-based hardening**: Production environments get additional security
- **File integrity monitoring**: Tracks changes to critical paths
- **Audit logging**: Security events logged in production
- **Log rotation**: Automatic management of log files
- **NATS authorization**: User/permission based access control

## 📊 Monitoring Stack

The template includes optional monitoring:
- **Prometheus**: Metrics collection
- **Grafana**: Visualization (non-prod environments)
- **Node Exporter**: System metrics
- **NATS Exporter**: NATS-specific metrics

## 📈 Event Tracking

All deployment activities are tracked as events:

```bash
# View current status from events
./scripts/event_query.sh status

# Show deployment timeline
./scripts/event_query.sh timeline

# View events for specific host
./scripts/event_query.sh events mac-studio-1

# Follow events in real-time
./scripts/event_query.sh tail

# Rebuild projections from events
./scripts/event_query.sh rebuild
```

Events are stored in:
- `events/` - Event stream (append-only)
- `projections/` - Current state projections

## 📞 Support

- Check NATS status: `curl http://[HOST]:8222/varz | jq`
- View logs: `ssh admin@[HOST] 'tail -f /var/log/nats/*.log'`
- Rebuild: `ssh admin@[HOST] 'darwin-rebuild switch'`
- Health check: `ssh admin@[HOST] './scripts/health_check.sh'`
- Event history: `./scripts/event_query.sh timeline`