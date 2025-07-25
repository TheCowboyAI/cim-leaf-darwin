#!/usr/bin/env bash
# Test event streaming functionality

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/event_store.sh"
source "${SCRIPT_DIR}/../lib/projections.sh"

echo "=== Testing Event Stream ==="
echo ""

# Create test events directory
export EVENT_STORE_DIR="/tmp/cim-test-events-$$"
export PROJECTIONS_DIR="/tmp/cim-test-projections-$$"
mkdir -p "$EVENT_STORE_DIR" "$PROJECTIONS_DIR"

echo "Test directories:"
echo "  Events: $EVENT_STORE_DIR"
echo "  Projections: $PROJECTIONS_DIR"
echo ""

# Simulate inventory extraction
echo "1. Simulating inventory extraction..."
CORRELATION_ID=$(generate_correlation_id)

emit_deployment_event "inventory.extraction.started" "test-mac-1" \
    '{"user": "admin", "host": "192.168.1.100"}' \
    "$CORRELATION_ID"

emit_deployment_event "inventory.hardware.discovered" "test-mac-1" \
    '{
        "system_info": {
            "hostname": "test-mac-1",
            "model": "Mac14,2",
            "serial_number": "TEST123456"
        },
        "hardware": {
            "cpu_type": "Apple M1 Pro",
            "memory_gb": 32
        }
    }' \
    "$CORRELATION_ID"

emit_deployment_event "inventory.extraction.completed" "test-mac-1" \
    '{"output_file": "/tmp/test-inventory.json", "size_bytes": "4096"}' \
    "$CORRELATION_ID"

echo "✓ Created $(wc -l < "$EVENT_STORE_DIR/events.jsonl") events"
echo ""

# Build projections
echo "2. Building projections..."
update_all_projections

echo "✓ Projections created:"
ls -la "$PROJECTIONS_DIR"
echo ""

# Show inventory projection
echo "3. Inventory Projection:"
load_projection "inventory" | jq '.hosts["test-mac-1"]'
echo ""

# Show deployment graph
echo "4. Deployment Graph Summary:"
load_projection "deployment_graph" | jq '{
    total_nodes: (.nodes | length),
    total_edges: (.edges | length),
    correlations: .correlations
}'
echo ""

# Query events by correlation
echo "5. Events in correlation $CORRELATION_ID:"
load_events_by_correlation "$CORRELATION_ID" | jq -r '.[] | "\(.timestamp) \(.event_type)"'
echo ""

# Simulate a second host
echo "6. Adding second host..."
CORRELATION_ID2=$(generate_correlation_id)

emit_deployment_event "inventory.extraction.started" "test-mac-2" \
    '{"user": "admin", "host": "192.168.1.101"}' \
    "$CORRELATION_ID2"

emit_deployment_event "inventory.extraction.failed" "test-mac-2" \
    '{"error": "SSH connection refused"}' \
    "$CORRELATION_ID2"

# Rebuild projections
update_all_projections

echo ""
echo "7. Updated Inventory Status:"
load_projection "inventory" | jq '{
    total_hosts: .total_hosts,
    by_status: .by_status
}'

# Clean up
echo ""
echo "Cleaning up test directories..."
rm -rf "$EVENT_STORE_DIR" "$PROJECTIONS_DIR"

echo ""
echo "✓ Event streaming test completed successfully!"