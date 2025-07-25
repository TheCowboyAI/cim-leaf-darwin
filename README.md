# CIM Leaf Darwin Template

A GitHub template repository for deploying CIM (Composable Information Machine) leaf nodes on Darwin (macOS) systems using nix-darwin.

## 🚀 Using This Template

### 1. Create Your Leaf Repository

1. Click "Use this template" on GitHub
2. Name your repository: `cim-leaf-[LEAF_NAME]` (e.g., `cim-leaf-tokyo-prod-1`)
3. Clone your new repository

### 2. Configure Your Leaf

Run the setup script to configure your specific leaf:

```bash
./scripts/setup_leaf.sh
```

This will prompt you for:
- **Leaf name**: Unique identifier (e.g., `tokyo-prod-1`)
- **Domain**: Business domain this leaf serves (e.g., `trading`, `analytics`)
- **Region**: Geographic region code
- **Environment**: dev/staging/prod
- **NATS cluster**: Name of your CIM cluster
- **Upstream host**: NATS server to connect to

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
├── leaf.config.json       # Leaf-specific configuration
├── modules/
│   ├── nats.nix          # NATS service configuration
│   └── domains/          # Domain-specific modules
│       └── [DOMAIN].nix  # Your domain configuration
├── inventory/            # Hardware inventories
├── hosts/               # Generated host configs
└── scripts/             # Deployment automation
```

## 🔧 Leaf Configuration

The `leaf.config.json` file contains:

```json
{
  "leaf": {
    "name": "tokyo-prod-1",
    "domain": "trading",
    "region": "ap-northeast-1",
    "environment": "prod"
  },
  "cim_domain": {
    "repository": "https://github.com/YourOrg/cim-domain-trading.git"
  },
  "nats": {
    "cluster_name": "cim-prod",
    "leaf_connections": [{
      "name": "upstream",
      "url": "nats://nats-hub.example.com:4222"
    }]
  }
}
```

## 🌐 Multi-Host Deployment

Add multiple hosts to your leaf:

1. Extract inventory for each host
2. Generate configurations
3. Update `leaf.config.json` with all target hosts
4. Deploy to each host

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

## 📞 Support

- Check NATS status: `curl http://[HOST]:8222/varz | jq`
- View logs: `ssh admin@[HOST] 'tail -f /var/log/nats/*.log'`
- Rebuild: `ssh admin@[HOST] 'darwin-rebuild switch'`
- Health check: `ssh admin@[HOST] './scripts/health_check.sh'`