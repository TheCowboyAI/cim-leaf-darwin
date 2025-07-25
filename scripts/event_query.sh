#!/usr/bin/env bash
# Query and visualize CIM leaf deployment events

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/event_store.sh"
source "${SCRIPT_DIR}/../lib/projections.sh"

usage() {
    cat << EOF
CIM Leaf Event Query Tool

Usage: $0 <command> [options]

Commands:
  status              Show current leaf and host status
  inventory           Show inventory projection
  graph               Show deployment graph
  timeline            Show event timeline
  events <host>       Show events for a specific host
  correlation <id>    Show all events in a correlation
  tail                Follow new events in real-time
  rebuild             Rebuild all projections from events

Options:
  -h, --help         Show this help message
  -j, --json         Output raw JSON
  -f, --format       Pretty format output (default)

Examples:
  $0 status
  $0 inventory --json
  $0 events mac-studio-1
  $0 correlation cor-abc123
  $0 tail
EOF
}

# Parse arguments
COMMAND=""
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
    case $1 in
        status|inventory|graph|timeline|events|correlation|tail|rebuild)
            COMMAND=$1
            shift
            if [[ "$COMMAND" == "events" || "$COMMAND" == "correlation" ]] && [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                FILTER_VALUE=$1
                shift
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -j|--json)
            OUTPUT_JSON=true
            shift
            ;;
        -f|--format)
            OUTPUT_JSON=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$COMMAND" ]; then
    usage
    exit 1
fi

# Helper to format JSON output
format_output() {
    if [ "$OUTPUT_JSON" = true ]; then
        cat
    else
        jq '.'
    fi
}

# Show current status
show_status() {
    echo "=== CIM Leaf Status ==="
    echo ""
    
    # Load projections
    local leaf_status=$(load_projection "leaf_status")
    local inventory=$(load_projection "inventory")
    
    if [ "$OUTPUT_JSON" = true ]; then
        jq -n \
            --argjson leaf "$leaf_status" \
            --argjson inventory "$inventory" \
            '{leaf: $leaf, inventory: $inventory}'
    else
        # Pretty print status
        echo "Leaf: $(echo "$leaf_status" | jq -r '.leaf_name')"
        echo "Setup: $(echo "$leaf_status" | jq -r '.setup_status')"
        echo ""
        
        echo "Hosts:"
        echo "$inventory" | jq -r '.hosts | to_entries[] | "  \(.key): \(.value.status)"'
        echo ""
        
        echo "Services:"
        echo "$leaf_status" | jq -r '.services | to_entries[] | "  \(.key): \(.value.status)"'
        echo ""
        
        echo "Last Operations:"
        echo "  Backup: $(echo "$leaf_status" | jq -r '.last_backup // "never"')"
        echo "  Health Check: $(echo "$leaf_status" | jq -r '.last_health_check // "never"')"
    fi
}

# Show inventory projection
show_inventory() {
    if [ "$OUTPUT_JSON" = true ]; then
        load_projection "inventory"
    else
        echo "=== Inventory Projection ==="
        echo ""
        
        local inventory=$(load_projection "inventory")
        
        echo "Total Hosts: $(echo "$inventory" | jq -r '.total_hosts')"
        echo "Last Updated: $(echo "$inventory" | jq -r '.last_updated')"
        echo ""
        
        echo "Status Summary:"
        echo "$inventory" | jq -r '.by_status | to_entries[] | "  \(.key): \(.value)"'
        echo ""
        
        echo "Host Details:"
        echo "$inventory" | jq -r '.hosts | to_entries[] | 
            "\(.key):\n  Status: \(.value.status)\n  Model: \(.value.hardware.system_info.model // "unknown")\n  Serial: \(.value.hardware.system_info.serial_number // "unknown")\n"'
    fi
}

# Show deployment graph
show_graph() {
    local graph=$(load_projection "deployment_graph")
    
    if [ "$OUTPUT_JSON" = true ]; then
        echo "$graph"
    else
        echo "=== Deployment Graph ==="
        echo ""
        
        echo "Nodes: $(echo "$graph" | jq '.nodes | length')"
        echo "Edges: $(echo "$graph" | jq '.edges | length')"
        echo "Correlations: $(echo "$graph" | jq '.correlations | length')"
        echo ""
        
        echo "Recent Events:"
        echo "$graph" | jq -r '.timeline | reverse | .[0:10][] | 
            "\(.timestamp) \(.type) [\(.aggregate_id)]"'
    fi
}

# Show timeline
show_timeline() {
    local limit="${1:-50}"
    
    echo "=== Event Timeline (last $limit events) ==="
    echo ""
    
    if [ "$OUTPUT_JSON" = true ]; then
        tail -n "$limit" "$EVENT_STORE_DIR/events.jsonl" 2>/dev/null | jq -s '.'
    else
        tail -n "$limit" "$EVENT_STORE_DIR/events.jsonl" 2>/dev/null | \
            jq -r '. | "\(.timestamp) \(.event_type) [\(.aggregate_id)] correlation:\(.correlation_id[0:8])"' | \
            sort -r
    fi
}

# Show events for a host
show_host_events() {
    local host="$1"
    
    echo "=== Events for $host ==="
    echo ""
    
    local events=$(load_aggregate_events "$host" "host")
    
    if [ "$OUTPUT_JSON" = true ]; then
        echo "$events"
    else
        echo "$events" | jq -r '.[] | "\(.timestamp) \(.event_type)"'
    fi
}

# Show correlation group
show_correlation() {
    local corr_id="$1"
    
    echo "=== Correlation: $corr_id ==="
    echo ""
    
    local events=$(load_events_by_correlation "$corr_id")
    
    if [ "$OUTPUT_JSON" = true ]; then
        echo "$events"
    else
        echo "$events" | jq -r '.[] | "\(.timestamp) \(.event_type) [\(.aggregate_id)]"' | sort
    fi
}

# Tail events in real-time
tail_events() {
    echo "=== Following events (Ctrl+C to stop) ==="
    echo ""
    
    tail -f "$EVENT_STORE_DIR/events.jsonl" 2>/dev/null | while IFS= read -r event; do
        if [ "$OUTPUT_JSON" = true ]; then
            echo "$event"
        else
            echo "$event" | jq -r '"\(.timestamp) \(.event_type) [\(.aggregate_id)] correlation:\(.correlation_id[0:8])"'
        fi
    done
}

# Rebuild projections
rebuild_projections() {
    echo "Rebuilding all projections from event stream..."
    update_all_projections
}

# Execute command
case "$COMMAND" in
    status)
        show_status
        ;;
    inventory)
        show_inventory
        ;;
    graph)
        show_graph
        ;;
    timeline)
        show_timeline
        ;;
    events)
        if [ -z "${FILTER_VALUE:-}" ]; then
            echo "Error: Host name required"
            usage
            exit 1
        fi
        show_host_events "$FILTER_VALUE"
        ;;
    correlation)
        if [ -z "${FILTER_VALUE:-}" ]; then
            echo "Error: Correlation ID required"
            usage
            exit 1
        fi
        show_correlation "$FILTER_VALUE"
        ;;
    tail)
        tail_events
        ;;
    rebuild)
        rebuild_projections
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac