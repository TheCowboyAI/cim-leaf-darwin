#!/usr/bin/env bash
# Test the template using Docker containers as mock Macs

set -euo pipefail

echo "=== CIM Leaf Darwin Docker Test ==="
echo ""
echo "This script simulates remote deployment using Docker containers"
echo ""

# Check prerequisites
if ! command -v docker &>/dev/null; then
    echo "Error: Docker is required for this test"
    echo "Install Docker or use local_test.sh instead"
    exit 1
fi

# Create test network
echo "Creating test network..."
docker network create cim-test 2>/dev/null || true

# Build test container image
echo "Building test container..."
cat > /tmp/Dockerfile.cim-test << 'EOF'
FROM ubuntu:22.04

# Install SSH server and dependencies
RUN apt-get update && apt-get install -y \
    openssh-server \
    curl \
    git \
    sudo \
    jq \
    netcat \
    && rm -rf /var/lib/apt/lists/*

# Create admin user
RUN useradd -m -s /bin/bash admin && \
    echo 'admin:admin' | chpasswd && \
    usermod -aG sudo admin && \
    echo 'admin ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Setup SSH
RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Create mock macOS commands
RUN echo '#!/bin/bash\necho "LocalHostName"' > /usr/local/bin/scutil && \
    chmod +x /usr/local/bin/scutil && \
    echo '#!/bin/bash\necho "ComputerName"' > /usr/local/bin/sw_vers && \
    chmod +x /usr/local/bin/sw_vers && \
    echo '#!/bin/bash\necho "Mac-1234567890"' > /usr/local/bin/system_profiler && \
    chmod +x /usr/local/bin/system_profiler && \
    echo '#!/bin/bash\necho "arm64"' > /usr/local/bin/uname && \
    chmod +x /usr/local/bin/uname

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
EOF

docker build -t cim-test-mac -f /tmp/Dockerfile.cim-test . 2>/dev/null

# Start test containers
echo ""
echo "Starting test containers..."

# Start NATS hub
docker run -d --name cim-nats-hub \
    --network cim-test \
    -p 4222:4222 \
    -p 8222:8222 \
    nats:latest \
    -js -m 8222

# Start mock Mac containers
for i in 1 2 3; do
    docker run -d --name cim-mac-$i \
        --network cim-test \
        -p 222$i:22 \
        cim-test-mac
done

# Wait for containers
echo "Waiting for containers to start..."
sleep 5

# Test deployment workflow
echo ""
echo "=== Testing Deployment Workflow ==="

# 1. Test inventory extraction
echo ""
echo "1. Testing inventory extraction..."
./scripts/extract_inventory.sh localhost:2221 admin 2>/dev/null || {
    echo "Note: Inventory extraction will partially fail on mock containers"
    echo "This is expected as they don't have real Mac hardware"
}

# Check if inventory was created
if [ -d "inventory/localhost" ]; then
    echo "✓ Inventory directory created"
    ls -la inventory/localhost/
else
    echo "✗ Inventory extraction needs a real Mac"
fi

# 2. Test health check
echo ""
echo "2. Testing health check script..."
./scripts/health_check.sh || true

# 3. Test backup script
echo ""
echo "3. Testing backup operations..."
./scripts/backup_restore.sh list

# 4. Test NATS connectivity
echo ""
echo "4. Testing NATS hub connectivity..."
if curl -s http://localhost:8222/varz | jq -r '.version' &>/dev/null; then
    echo "✓ NATS hub is running"
    echo "  Version: $(curl -s http://localhost:8222/varz | jq -r '.version')"
    echo "  Health: $(curl -s http://localhost:8222/healthz)"
else
    echo "✗ NATS hub connection failed"
fi

# 5. Test monitoring endpoints
echo ""
echo "5. Testing monitoring endpoints..."
echo "Note: Monitoring services require full deployment"

# Cleanup function
cleanup() {
    echo ""
    echo "=== Cleaning up test environment ==="
    docker stop cim-nats-hub cim-mac-1 cim-mac-2 cim-mac-3 2>/dev/null || true
    docker rm cim-nats-hub cim-mac-1 cim-mac-2 cim-mac-3 2>/dev/null || true
    docker network rm cim-test 2>/dev/null || true
    rm -f /tmp/Dockerfile.cim-test
    echo "✓ Cleanup complete"
}

trap cleanup EXIT

echo ""
echo "=== Interactive Test Options ==="
echo ""
echo "The test environment is running. You can now:"
echo ""
echo "1. SSH into mock Macs:"
echo "   ssh admin@localhost -p 2221  # password: admin"
echo ""
echo "2. Check NATS hub:"
echo "   curl http://localhost:8222/varz | jq"
echo ""
echo "3. Test setup script:"
echo "   ./scripts/setup_leaf.sh"
echo ""
echo "4. View container logs:"
echo "   docker logs cim-nats-hub"
echo ""
echo "Press Enter to stop the test environment..."
read -r

echo ""
echo "Test completed!"