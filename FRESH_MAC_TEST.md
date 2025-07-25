# Testing CIM Leaf Darwin on a Fresh Mac

This guide tests the template on a fresh Mac while preserving a clean environment.

## Prerequisites

Your Mac should have:
- Fresh macOS installation
- Local user account (not Apple ID)
- Completed system updates
- Internet connection

## Step 0: Install Command Line Developer Tools

**This is required before anything else!**

```bash
# Open Terminal (Cmd+Space, type "Terminal")

# Install Command Line Developer Tools
xcode-select --install

# A dialog will appear asking to install the tools
# Click "Install" and agree to the license
# This will take 5-15 minutes depending on internet speed

# Verify installation
xcode-select -p
# Should output: /Library/Developer/CommandLineTools

# Verify git is available
git --version
# Should show: git version X.X.X
```

**Note**: You do NOT need the full Xcode, just the Command Line Tools.

## Step 1: Enable SSH Access (for remote deployment)

On the test Mac:

```bash
# Open Terminal (Cmd+Space, type "Terminal")

# Enable SSH
sudo systemsetup -setremotelogin on

# Verify SSH is enabled
sudo systemsetup -getremotelogin

# Get your IP address
ipconfig getifaddr en0
# Note this IP address for later (e.g., 192.168.1.100)
```

## Step 2: Install Nix (Required)

We'll install Nix which is needed for the deployment:

```bash
# Install the Determinate Systems Nix (recommended for Mac)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install --no-confirm

# The installer will ask for sudo password
# Accept the default options
```

After installation completes:

```bash
# Close Terminal completely (Cmd+Q)
# Open a new Terminal window
# Verify Nix is installed
nix --version
```

## Step 3: Create Test Directory

```bash
# Create a clean workspace
mkdir -p ~/cim-test
cd ~/cim-test
```

## Step 4: Clone and Test the Template

From your development machine (where you have the template):

```bash
# First, commit and push the template
cd /git/thecowboyai/cim-leaf-darwin
git add -A
git commit -m "Complete CIM Leaf Darwin template"
git push origin main

# Note your repository URL
```

On the test Mac:

```bash
# Clone the template
cd ~/cim-test
git clone https://github.com/TheCowboyAI/cim-leaf-darwin.git
cd cim-leaf-darwin

# Verify the template is complete
./test/validate_template.sh
```

## Step 5: Test Template Setup Process

First, configure your leaf by editing the Nix files:

```bash
# Copy example configuration
cp examples/configs/dev-local.nix leaf-config.nix

# Edit the configuration
# Replace USER with your actual username where needed
# Update any other settings as desired
nano leaf-config.nix
```

Then run the deterministic setup:

```bash
# Run the setup script
./scripts/setup_leaf_deterministic.sh
```

The script will:
- Read configuration from `leaf-config.nix`
- Display the configuration for confirmation
- Generate domain modules and JSON configs
- Initialize event tracking

Verify the setup:

```bash
# Check configuration was created
cat leaf.config.json

# Check domain module was created
ls modules/domains/

# Check git was configured
git config user.name

# Check event stream initialized
./scripts/event_query.sh status
```

## Step 6: Test Local Deployment

### 6.1 Build the Configuration

```bash
# This will download dependencies and build the configuration
# First time will take several minutes
darwin-rebuild build --flake .
```

### 6.2 Apply the Configuration

```bash
# This actually applies the configuration to your Mac
# It will ask for sudo password
darwin-rebuild switch --flake .
```

### 6.3 Verify Services

```bash
# Check if NATS is running
sudo launchctl list | grep nats

# Check NATS health
curl http://localhost:8222/healthz

# Run full health check
./scripts/health_check.sh
```

## Step 7: Test Operational Scripts

### 7.1 Backup Testing

```bash
# Create a backup
./scripts/backup_restore.sh backup

# List backups
./scripts/backup_restore.sh list
```

### 7.2 Monitoring Check

```bash
# Check monitoring services
curl http://localhost:9090/-/healthy  # Prometheus
curl http://localhost:9100/metrics | head -20  # Node exporter

# In dev environment, Grafana should be available
open http://localhost:3000  # Opens in browser
# Default login: admin / test-mac-1-admin
```

### 7.3 Maintenance Operations

```bash
# Check system status
./scripts/maintenance.sh status

# Force log rotation
./scripts/maintenance.sh rotate-logs
```

## Step 8: Test Remote Deployment (Optional)

If you have another Mac available, test remote deployment:

From the test Mac:

```bash
# Extract inventory from a remote Mac
./scripts/extract_inventory.sh 192.168.1.101 admin

# Generate configuration
./scripts/generate_config.sh remote-mac-1

# Deploy to remote
./scripts/deploy_host.sh remote-mac-1 192.168.1.101 admin
```

## Step 9: Test Template Fork Process

```bash
# Commit your changes
git add -A
git commit -m "Configure test-mac-1 leaf"

# This simulates what happens when someone uses your template
```

## Step 10: Cleanup (Restore Clean State)

To completely remove the deployment and restore your Mac:

```bash
# Stop all services
sudo launchctl unload /Library/LaunchDaemons/org.nixos.*

# Remove nix-darwin
nix-build '<darwin>' -A uninstaller
./result/bin/darwin-uninstaller

# Remove Nix completely (optional)
/nix/nix-installer uninstall

# Remove test directory
cd ~
rm -rf ~/cim-test

# Disable SSH if you enabled it
sudo systemsetup -setremotelogin off

# Restart your Mac to ensure clean state
sudo reboot
```

## What Success Looks Like

✅ **Setup Success**:
- `leaf.config.json` created with your values
- `modules/domains/testing.nix` exists
- No template files remain

✅ **Deployment Success**:
- `darwin-rebuild switch` completes without errors
- NATS responds to health checks
- `./scripts/health_check.sh` shows all green

✅ **Operational Success**:
- Backups create successfully
- Monitoring endpoints respond
- Maintenance scripts run without errors

## Troubleshooting

### "darwin-rebuild: command not found"

```bash
# After first run, you may need to source the profile
source /etc/static/bashrc
# Or open a new terminal
```

### "NATS not starting"

```bash
# Check logs
tail -f /var/log/nats/error.log

# Check if port is in use
sudo lsof -i :4222

# Manually start
sudo launchctl load -w /Library/LaunchDaemons/org.nixos.nats.plist
```

### Permission Issues

```bash
# Some commands need sudo
sudo darwin-rebuild switch --flake .
```

## Quick Test Summary

For the absolute minimum test:

```bash
# 0. Install Command Line Developer Tools (if not already installed)
xcode-select --install
# Wait for installation to complete (5-15 minutes)

# 1. Install Nix (one-time)
curl -L https://install.determinate.systems/nix | sh -s -- install

# 2. Clone template
git clone <your-repo> && cd cim-leaf-darwin

# 3. Setup (configure first!)
cp examples/configs/dev-local.nix leaf-config.nix
# Edit leaf-config.nix if needed
./scripts/setup_leaf_deterministic.sh

# 4. Deploy
darwin-rebuild switch --flake .

# 5. Verify
./scripts/health_check.sh
```

This will confirm the template works end-to-end on a real Mac!