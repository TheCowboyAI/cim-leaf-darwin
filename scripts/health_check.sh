#!/usr/bin/env bash
# Health check script for CIM leaf node

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load configuration if available
if [ -f "leaf.config.json" ]; then
    LEAF_NAME=$(jq -r '.leaf.name' leaf.config.json)
    DOMAIN=$(jq -r '.leaf.domain' leaf.config.json)
else
    LEAF_NAME="unknown"
    DOMAIN="unknown"
fi

echo "=== CIM Leaf Health Check ==="
echo "Leaf: $LEAF_NAME"
echo "Domain: $DOMAIN"
echo "Time: $(date)"
echo ""

# Track overall health
HEALTH_STATUS=0

# Function to check service
check_service() {
    local service_name=$1
    local check_command=$2
    local service_label=$3
    
    echo -n "Checking $service_label... "
    
    if eval "$check_command" &>/dev/null; then
        echo -e "${GREEN}✓ OK${NC}"
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        HEALTH_STATUS=1
        return 1
    fi
}

# Function to check port
check_port() {
    local port=$1
    local service=$2
    
    echo -n "Checking $service port ($port)... "
    
    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${GREEN}✓ OPEN${NC}"
        return 0
    else
        echo -e "${RED}✗ CLOSED${NC}"
        HEALTH_STATUS=1
        return 1
    fi
}

# Function to check disk space
check_disk_space() {
    local path=$1
    local threshold=90
    
    echo -n "Checking disk space for $path... "
    
    local usage=$(df -h "$path" | awk 'NR==2 {print int($5)}')
    
    if [ "$usage" -lt "$threshold" ]; then
        echo -e "${GREEN}✓ ${usage}% used${NC}"
        return 0
    else
        echo -e "${RED}✗ ${usage}% used (threshold: ${threshold}%)${NC}"
        HEALTH_STATUS=1
        return 1
    fi
}

echo "=== Service Checks ==="

# Check NATS
check_service "NATS Server" "curl -s http://localhost:8222/healthz" "NATS Server"
check_port 4222 "NATS Client"
check_port 8222 "NATS Monitor"

# Check NATS JetStream if NATS is running
if curl -s http://localhost:8222/healthz &>/dev/null; then
    echo -n "Checking NATS JetStream... "
    JS_INFO=$(curl -s http://localhost:8222/jsz)
    if [ $? -eq 0 ] && echo "$JS_INFO" | jq -e '.config' &>/dev/null; then
        STREAMS=$(echo "$JS_INFO" | jq -r '.streams // 0')
        CONSUMERS=$(echo "$JS_INFO" | jq -r '.consumers // 0')
        echo -e "${GREEN}✓ OK (Streams: $STREAMS, Consumers: $CONSUMERS)${NC}"
    else
        echo -e "${YELLOW}⚠ No JetStream info available${NC}"
    fi
fi

# Check monitoring if enabled
if [ -f "/etc/prometheus/prometheus.yml" ]; then
    echo ""
    echo "=== Monitoring Checks ==="
    check_service "Prometheus" "curl -s http://localhost:9090/-/healthy" "Prometheus"
    check_port 9100 "Node Exporter"
    check_port 7777 "NATS Exporter"
    
    # Check Grafana in non-prod environments
    if [ -f "/etc/grafana/grafana.ini" ]; then
        check_service "Grafana" "curl -s http://localhost:3000/api/health" "Grafana"
    fi
fi

echo ""
echo "=== System Checks ==="

# Check disk space
check_disk_space "/"
check_disk_space "/var/lib/nats" 2>/dev/null || echo -e "${YELLOW}⚠ NATS data directory not found${NC}"

# Check memory
echo -n "Checking memory usage... "
if command -v vm_stat &>/dev/null; then
    # macOS
    MEMORY_PRESSURE=$(memory_pressure | grep "System-wide memory free percentage" | awk '{print $5}' | tr -d '%')
    if [ "$MEMORY_PRESSURE" -gt 20 ]; then
        echo -e "${GREEN}✓ ${MEMORY_PRESSURE}% free${NC}"
    else
        echo -e "${YELLOW}⚠ ${MEMORY_PRESSURE}% free${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Unable to check (not macOS)${NC}"
fi

# Check launchd services
echo ""
echo "=== Launchd Services ==="
for service in nats prometheus node-exporter; do
    echo -n "Checking $service daemon... "
    if sudo launchctl list | grep -q "org.*$service"; then
        PID=$(sudo launchctl list | grep "org.*$service" | awk '{print $1}')
        if [ "$PID" != "-" ]; then
            echo -e "${GREEN}✓ Running (PID: $PID)${NC}"
        else
            echo -e "${RED}✗ Not running${NC}"
            HEALTH_STATUS=1
        fi
    else
        echo -e "${YELLOW}⚠ Not configured${NC}"
    fi
done

# Check NATS connectivity if configured
if [ -f "leaf.config.json" ]; then
    echo ""
    echo "=== NATS Cluster Connectivity ==="
    
    UPSTREAM_URL=$(jq -r '.nats.leaf_connections[0].url // empty' leaf.config.json)
    if [ -n "$UPSTREAM_URL" ]; then
        echo -n "Checking upstream connection to $UPSTREAM_URL... "
        UPSTREAM_HOST=$(echo "$UPSTREAM_URL" | sed 's|nats://||' | cut -d: -f1)
        UPSTREAM_PORT=$(echo "$UPSTREAM_URL" | sed 's|nats://||' | cut -d: -f2)
        
        if nc -z -w2 "$UPSTREAM_HOST" "$UPSTREAM_PORT" 2>/dev/null; then
            echo -e "${GREEN}✓ Reachable${NC}"
        else
            echo -e "${RED}✗ Unreachable${NC}"
            HEALTH_STATUS=1
        fi
    fi
fi

# Summary
echo ""
echo "=== Health Check Summary ==="
if [ $HEALTH_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed - System is healthy${NC}"
else
    echo -e "${RED}✗ Some checks failed - System needs attention${NC}"
fi

exit $HEALTH_STATUS