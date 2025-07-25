# Testing CIM Leaf Darwin Template

This directory contains test scripts to validate the template functionality.

## Quick Test

Run the local test to validate the template structure and setup process:

```bash
./test/local_test.sh
```

This test:
- Checks all required files exist
- Validates script syntax
- Tests the setup process
- Verifies Nix flake evaluation
- Runs basic health checks

## Docker-based Testing

For more comprehensive testing with mock remote hosts:

```bash
./test/docker_test.sh
```

This creates:
- A NATS hub container
- Mock Mac containers (Ubuntu with SSH)
- Test network for connectivity

## Manual Testing on Real Mac

### 1. Local Setup Test

```bash
# Clone the template
git clone <repo> test-leaf
cd test-leaf

# Run setup
./scripts/setup_leaf.sh

# Answer the prompts:
# - Leaf name: test-local
# - Description: Test deployment
# - Domain: testing
# - Region: local
# - Environment: dev
# - GitHub org: myorg
# - Cluster: test-cluster
# - Upstream: localhost

# Verify setup
cat leaf.config.json
ls modules/domains/
```

### 2. Local Deployment Test

If you have nix-darwin installed:

```bash
# Build configuration
darwin-rebuild build --flake .

# Check services
./scripts/health_check.sh

# Test NATS
curl http://localhost:8222/varz | jq
```

### 3. Remote Deployment Test

With two Macs on the same network:

```bash
# From Mac 1 (controller):
./scripts/extract_inventory.sh 192.168.1.100 admin

# Generate config
./scripts/generate_config.sh mac-studio-1

# Deploy
./scripts/deploy_host.sh mac-studio-1 192.168.1.100 admin

# Verify
ssh admin@192.168.1.100 'curl http://localhost:8222/healthz'
```

## GitHub Template Test

1. Push to GitHub as a template repository
2. Click "Use this template"
3. Clone the new repository
4. Run `./scripts/setup_leaf.sh`
5. Verify the template cleanup workflow runs

## Testing Checklist

### Template Structure
- [ ] All scripts are executable
- [ ] Template config has all placeholders
- [ ] Example domain is complete
- [ ] Documentation is clear

### Setup Process
- [ ] Setup script runs without errors
- [ ] Configuration is correctly generated
- [ ] Domain module is created
- [ ] Git config is updated

### Deployment
- [ ] Inventory extraction works
- [ ] Config generation succeeds
- [ ] Remote deployment completes
- [ ] Services start correctly

### Operations
- [ ] Health check reports correctly
- [ ] Backup/restore functions
- [ ] Monitoring works (if enabled)
- [ ] Maintenance scripts run

### Security
- [ ] Production mode enables hardening
- [ ] Log rotation works
- [ ] File integrity monitoring runs

## Troubleshooting

### Common Issues

1. **Nix not found**
   ```bash
   # Install Nix first
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

2. **Permission denied**
   ```bash
   # Ensure scripts are executable
   chmod +x scripts/*.sh
   ```

3. **SSH connection failed**
   ```bash
   # Check SSH access
   ssh -v admin@target-host
   ```

4. **NATS not starting**
   ```bash
   # Check launchd logs
   sudo launchctl list | grep nats
   tail -f /var/log/nats/error.log
   ```

## Performance Testing

For production deployments, test:

1. **NATS throughput**
   ```bash
   nats bench test --msgs 100000 --size 1024
   ```

2. **JetStream performance**
   ```bash
   nats stream add TEST --subjects "test.>" 
   nats bench test --msgs 10000 --size 1024 --js
   ```

3. **Resource usage**
   ```bash
   ./scripts/maintenance.sh status
   ```