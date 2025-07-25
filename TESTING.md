# Testing Guide for CIM Leaf Darwin

## Quick Validation

Run this first to ensure the template is complete:

```bash
./test/validate_template.sh
```

## Testing Methods

### 1. Local Testing (Recommended First Step)

Test the template without deployment:

```bash
./test/local_test.sh
```

This validates:
- File structure
- Script syntax  
- Setup process
- Basic functionality

### 2. Template Setup Test

Test the setup process manually:

```bash
# In a temporary directory
cp -r /path/to/template /tmp/test-leaf
cd /tmp/test-leaf
./scripts/setup_leaf.sh

# Enter test values:
# - Leaf name: test-1
# - Description: Test leaf
# - Domain: testing
# - Region: local
# - Environment: dev
# - GitHub org: myorg
# - Cluster: test
# - Upstream: localhost
```

### 3. Docker-based Testing

For testing remote deployment workflow:

```bash
./test/docker_test.sh
```

This creates mock infrastructure with:
- NATS server
- SSH-enabled containers
- Test network

### 4. Real Mac Testing

If you have access to a Mac:

#### Local Deployment
```bash
# After running setup_leaf.sh
darwin-rebuild build --flake .
./scripts/health_check.sh
```

#### Remote Deployment
```bash
# Extract inventory
./scripts/extract_inventory.sh 192.168.1.100

# Generate config
./scripts/generate_config.sh mac-studio-1

# Deploy
./scripts/deploy_host.sh mac-studio-1 192.168.1.100
```

## What to Test

### Template Functionality
- [x] All files present
- [x] Scripts executable
- [x] Placeholders in template
- [ ] Setup script works
- [ ] Config generation works
- [ ] Domain module created

### Deployment Testing
- [ ] Inventory extraction
- [ ] Host config generation
- [ ] Remote deployment
- [ ] Service startup

### Operational Testing  
- [ ] Health checks run
- [ ] Backup/restore works
- [ ] Monitoring accessible
- [ ] Maintenance scripts work

### Security Testing
- [ ] Production mode hardening
- [ ] Log rotation
- [ ] File integrity monitoring

## Common Test Scenarios

### 1. Multiple Leaf Setup
```bash
# Create leaves for different domains
./scripts/setup_leaf.sh  # Domain: trading
./scripts/setup_leaf.sh  # Domain: analytics
```

### 2. Environment-specific Testing
```bash
# Test with production settings
# Environment: prod (when prompted)
```

### 3. Failure Recovery
```bash
# Test backup/restore
./scripts/backup_restore.sh backup
./scripts/backup_restore.sh list
./scripts/backup_restore.sh restore <timestamp>
```

## Verifying GitHub Template

1. Push to GitHub:
   ```bash
   git add -A
   git commit -m "Initial template"
   git push
   ```

2. Enable template in repository settings:
   - Go to Settings → General
   - Check "Template repository"

3. Test template usage:
   - Click "Use this template"
   - Create new repository
   - Clone and run `setup_leaf.sh`

## Troubleshooting Tests

### Nix Issues
```bash
# Check Nix installation
nix --version

# Install if missing
sh <(curl -L https://nixos.org/nix/install) --daemon
```

### SSH Issues  
```bash
# Test SSH connectivity
ssh -v admin@target-host

# Check SSH service
sudo systemsetup -getremotelogin
```

### NATS Issues
```bash
# Check if port is in use
lsof -i :4222

# Check launchd
sudo launchctl list | grep nats
```

## Performance Testing

After deployment:

```bash
# NATS performance
nats bench test --msgs 100000

# System load
./scripts/maintenance.sh status

# Monitor resources
top -o cpu
```