#!/usr/bin/env bash
# Projection builders for CIM leaf deployment state

# Source event store
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/event_store.sh"

# Build inventory projection
build_inventory_projection() {
    echo "Building inventory projection..." >&2
    
    # Initialize projection state
    local projection='{
        "hosts": {},
        "last_updated": null,
        "total_hosts": 0,
        "by_status": {
            "discovered": 0,
            "configured": 0,
            "deployed": 0,
            "failed": 0
        }
    }'
    
    # Process all events
    while IFS= read -r event; do
        local event_type=$(echo "$event" | jq -r '.event_type')
        local aggregate_id=$(echo "$event" | jq -r '.aggregate_id')
        local timestamp=$(echo "$event" | jq -r '.timestamp')
        local data=$(echo "$event" | jq '.data')
        
        case "$event_type" in
            "inventory.extraction.started")
                projection=$(echo "$projection" | jq \
                    --arg host "$aggregate_id" \
                    --arg timestamp "$timestamp" \
                    '.hosts[$host] = {
                        host: $host,
                        status: "extracting",
                        extraction_started_at: $timestamp,
                        events: []
                    } + (.hosts[$host] // {})')
                ;;
                
            "inventory.hardware.discovered")
                projection=$(echo "$projection" | jq \
                    --arg host "$aggregate_id" \
                    --arg timestamp "$timestamp" \
                    --argjson hw_data "$data" \
                    '.hosts[$host] = (.hosts[$host] // {}) + {
                        status: "discovered",
                        discovered_at: $timestamp,
                        hardware: $hw_data
                    }')
                ;;
                
            "inventory.extraction.completed")
                projection=$(echo "$projection" | jq \
                    --arg host "$aggregate_id" \
                    --arg timestamp "$timestamp" \
                    --argjson event_data "$data" \
                    '.hosts[$host] = (.hosts[$host] // {}) + {
                        status: "inventory_complete",
                        extraction_completed_at: $timestamp,
                        inventory_file: $event_data.output_file
                    }')
                ;;
                
            "inventory.extraction.failed")
                projection=$(echo "$projection" | jq \
                    --arg host "$aggregate_id" \
                    --arg timestamp "$timestamp" \
                    --argjson event_data "$data" \
                    '.hosts[$host] = (.hosts[$host] // {}) + {
                        status: "failed",
                        failed_at: $timestamp,
                        error: $event_data.error
                    }')
                ;;
                
            "config.generation.completed")
                projection=$(echo "$projection" | jq \
                    --arg host "$aggregate_id" \
                    --arg timestamp "$timestamp" \
                    '.hosts[$host] = (.hosts[$host] // {}) + {
                        status: "configured",
                        configured_at: $timestamp
                    }')
                ;;
                
            "deployment.completed")
                projection=$(echo "$projection" | jq \
                    --arg host "$aggregate_id" \
                    --arg timestamp "$timestamp" \
                    '.hosts[$host] = (.hosts[$host] // {}) + {
                        status: "deployed",
                        deployed_at: $timestamp
                    }')
                ;;
        esac
        
        # Track event in host
        projection=$(echo "$projection" | jq \
            --arg host "$aggregate_id" \
            --arg event_id "$(echo "$event" | jq -r '.event_id')" \
            --arg event_type "$event_type" \
            --arg timestamp "$timestamp" \
            '.hosts[$host].events = ((.hosts[$host].events // []) + [{
                event_id: $event_id,
                event_type: $event_type,
                timestamp: $timestamp
            }])')
            
    done < <(cat "$EVENT_STORE_DIR/events.jsonl" 2>/dev/null | grep -E '"aggregate_type":\s*"host"' || true)
    
    # Calculate summary statistics
    projection=$(echo "$projection" | jq '
        .total_hosts = (.hosts | length) |
        .by_status = (.hosts | to_entries | map(.value.status) | group_by(.) | 
            map({(.[0]): length}) | add // {}) |
        .last_updated = now | strftime("%Y-%m-%dT%H:%M:%SZ")
    ')
    
    echo "$projection"
}

# Build deployment graph projection
build_deployment_graph() {
    echo "Building deployment graph projection..." >&2
    
    # Initialize graph structure
    local graph='{
        "nodes": {},
        "edges": [],
        "correlations": {},
        "timeline": []
    }'
    
    # Process all events to build graph
    while IFS= read -r event; do
        local event_id=$(echo "$event" | jq -r '.event_id')
        local event_type=$(echo "$event" | jq -r '.event_type')
        local aggregate_id=$(echo "$event" | jq -r '.aggregate_id')
        local timestamp=$(echo "$event" | jq -r '.timestamp')
        local correlation_id=$(echo "$event" | jq -r '.correlation_id')
        local causation_id=$(echo "$event" | jq -r '.causation_id')
        
        # Add node for this event
        graph=$(echo "$graph" | jq \
            --arg node_id "$event_id" \
            --arg event_type "$event_type" \
            --arg aggregate_id "$aggregate_id" \
            --arg timestamp "$timestamp" \
            --arg correlation_id "$correlation_id" \
            '.nodes[$node_id] = {
                id: $node_id,
                type: $event_type,
                aggregate_id: $aggregate_id,
                timestamp: $timestamp,
                correlation_id: $correlation_id
            }')
        
        # Add edge if there's a causation relationship
        if [ "$causation_id" != "null" ] && [ -n "$causation_id" ]; then
            graph=$(echo "$graph" | jq \
                --arg from "$causation_id" \
                --arg to "$event_id" \
                '.edges += [{from: $from, to: $to, type: "caused"}]')
        fi
        
        # Track correlation groups
        if [ "$correlation_id" != "null" ] && [ -n "$correlation_id" ]; then
            graph=$(echo "$graph" | jq \
                --arg corr_id "$correlation_id" \
                --arg event_id "$event_id" \
                '.correlations[$corr_id] = ((.correlations[$corr_id] // []) + [$event_id])')
        fi
        
        # Add to timeline
        graph=$(echo "$graph" | jq \
            --arg event_id "$event_id" \
            --arg timestamp "$timestamp" \
            --arg event_type "$event_type" \
            --arg aggregate_id "$aggregate_id" \
            '.timeline += [{
                event_id: $event_id,
                timestamp: $timestamp,
                type: $event_type,
                aggregate_id: $aggregate_id
            }] | .timeline |= sort_by(.timestamp)')
            
    done < <(cat "$EVENT_STORE_DIR/events.jsonl" 2>/dev/null || true)
    
    echo "$graph"
}

# Build leaf status projection
build_leaf_status_projection() {
    local leaf_name="${1:-$(jq -r '.leaf.name' leaf.config.json 2>/dev/null || echo "unknown")}"
    
    echo "Building leaf status projection..." >&2
    
    local projection='{
        "leaf_name": "'"$leaf_name"'",
        "setup_status": "not_started",
        "hosts": [],
        "services": {},
        "last_backup": null,
        "last_health_check": null,
        "timeline": []
    }'
    
    # Process setup events
    while IFS= read -r event; do
        local event_type=$(echo "$event" | jq -r '.event_type')
        local timestamp=$(echo "$event" | jq -r '.timestamp')
        local data=$(echo "$event" | jq '.data')
        
        case "$event_type" in
            "leaf.setup.started")
                projection=$(echo "$projection" | jq '.setup_status = "in_progress"')
                ;;
            "leaf.setup.completed")
                projection=$(echo "$projection" | jq '.setup_status = "completed"')
                ;;
            "leaf.setup.failed")
                projection=$(echo "$projection" | jq '.setup_status = "failed"')
                ;;
        esac
    done < <(load_events_by_type "leaf.setup.*" | jq -c '.[]')
    
    # Get deployed hosts
    local inventory_proj=$(build_inventory_projection)
    projection=$(echo "$projection" | jq \
        --argjson hosts "$(echo "$inventory_proj" | jq '[.hosts | to_entries | .[] | select(.value.status == "deployed") | .key]')" \
        '.hosts = $hosts')
    
    # Track service status
    while IFS= read -r event; do
        local event_type=$(echo "$event" | jq -r '.event_type')
        local service=$(echo "$event_type" | cut -d. -f2)
        local status=$(echo "$event_type" | cut -d. -f3)
        local timestamp=$(echo "$event" | jq -r '.timestamp')
        
        projection=$(echo "$projection" | jq \
            --arg service "$service" \
            --arg status "$status" \
            --arg timestamp "$timestamp" \
            '.services[$service] = {status: $status, last_update: $timestamp}')
    done < <(grep -E '"event_type":\s*"service\.' "$EVENT_STORE_DIR/events.jsonl" 2>/dev/null | jq -c '.' || true)
    
    # Track operational events
    local last_backup=$(load_events_by_type "backup.completed" | jq -r 'last.timestamp // null')
    local last_health=$(load_events_by_type "service.*.health_check" | jq -r 'last.timestamp // null')
    
    projection=$(echo "$projection" | jq \
        --arg backup "$last_backup" \
        --arg health "$last_health" \
        '.last_backup = $backup | .last_health_check = $health')
    
    echo "$projection"
}

# Update all projections
update_all_projections() {
    echo "Updating all projections..."
    
    # Update inventory projection
    build_inventory_projection | save_projection "inventory"
    
    # Update deployment graph
    build_deployment_graph | save_projection "deployment_graph"
    
    # Update leaf status
    build_leaf_status_projection | save_projection "leaf_status"
    
    echo "✓ All projections updated"
}

# Export functions
export -f build_inventory_projection
export -f build_deployment_graph
export -f build_leaf_status_projection
export -f update_all_projections