#!/usr/bin/env bash
# Event store functions for CIM leaf deployment tracking

# Event store location
EVENT_STORE_DIR="${EVENT_STORE_DIR:-./events}"
PROJECTIONS_DIR="${PROJECTIONS_DIR:-./projections}"

# Ensure directories exist
mkdir -p "$EVENT_STORE_DIR" "$PROJECTIONS_DIR"

# Generate event ID
generate_event_id() {
    echo "evt-$(date +%s%N)-$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 8)"
}

# Generate correlation ID for related events
generate_correlation_id() {
    echo "cor-$(uuidgen | tr '[:upper:]' '[:lower:]' | head -c 16)"
}

# Emit an event
emit_event() {
    local event_type="$1"
    local aggregate_id="$2"
    local aggregate_type="$3"
    local data="$4"
    local correlation_id="${5:-}"
    local causation_id="${6:-}"
    
    local event_id=$(generate_event_id)
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    
    # Create event
    local event=$(jq -n \
        --arg event_id "$event_id" \
        --arg event_type "$event_type" \
        --arg aggregate_id "$aggregate_id" \
        --arg aggregate_type "$aggregate_type" \
        --arg timestamp "$timestamp" \
        --arg correlation_id "$correlation_id" \
        --arg causation_id "$causation_id" \
        --argjson data "$data" \
        '{
            event_id: $event_id,
            event_type: $event_type,
            aggregate_id: $aggregate_id,
            aggregate_type: $aggregate_type,
            timestamp: $timestamp,
            correlation_id: $correlation_id,
            causation_id: $causation_id,
            data: $data
        }')
    
    # Append to event stream
    echo "$event" >> "$EVENT_STORE_DIR/events.jsonl"
    
    # Also write to daily partition for easier querying
    local date_partition=$(date +%Y-%m-%d)
    echo "$event" >> "$EVENT_STORE_DIR/events-${date_partition}.jsonl"
    
    # Return event for chaining
    echo "$event"
}

# Load events for an aggregate
load_aggregate_events() {
    local aggregate_id="$1"
    local aggregate_type="${2:-}"
    
    if [ ! -f "$EVENT_STORE_DIR/events.jsonl" ]; then
        echo "[]"
        return
    fi
    
    if [ -z "$aggregate_type" ]; then
        cat "$EVENT_STORE_DIR/events.jsonl" | jq -s "map(select(.aggregate_id == \"$aggregate_id\"))" 2>/dev/null || echo "[]"
    else
        cat "$EVENT_STORE_DIR/events.jsonl" | jq -s "map(select(.aggregate_id == \"$aggregate_id\" and .aggregate_type == \"$aggregate_type\"))" 2>/dev/null || echo "[]"
    fi
}

# Load events by type
load_events_by_type() {
    local event_type="$1"
    
    if [ ! -f "$EVENT_STORE_DIR/events.jsonl" ]; then
        echo "[]"
        return
    fi
    
    cat "$EVENT_STORE_DIR/events.jsonl" | jq -s "map(select(.event_type == \"$event_type\"))" 2>/dev/null || echo "[]"
}

# Load events by correlation ID
load_events_by_correlation() {
    local correlation_id="$1"
    
    if [ ! -f "$EVENT_STORE_DIR/events.jsonl" ]; then
        echo "[]"
        return
    fi
    
    cat "$EVENT_STORE_DIR/events.jsonl" | jq -s "map(select(.correlation_id == \"$correlation_id\"))" 2>/dev/null || echo "[]"
}

# Save projection
save_projection() {
    local projection_name="$1"
    local projection_data="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    
    # Add metadata to projection
    local projection=$(echo "$projection_data" | jq \
        --arg timestamp "$timestamp" \
        --arg name "$projection_name" \
        '. + {
            _projection: {
                name: $name,
                updated_at: $timestamp
            }
        }')
    
    # Save projection
    echo "$projection" > "$PROJECTIONS_DIR/${projection_name}.json"
}

# Load projection
load_projection() {
    local projection_name="$1"
    local projection_file="$PROJECTIONS_DIR/${projection_name}.json"
    
    if [ -f "$projection_file" ]; then
        cat "$projection_file"
    else
        echo "{}"
    fi
}

# Event types for leaf deployment
declare -a EVENT_TYPES=(
    # Setup events
    "leaf.setup.started"
    "leaf.setup.configured"
    "leaf.setup.completed"
    "leaf.setup.failed"
    
    # Inventory events
    "inventory.extraction.started"
    "inventory.extraction.completed"
    "inventory.extraction.failed"
    "inventory.hardware.discovered"
    
    # Configuration events
    "config.generation.started"
    "config.generation.completed"
    "config.generation.failed"
    
    # Deployment events
    "deployment.started"
    "deployment.nix.installing"
    "deployment.nix.installed"
    "deployment.darwin.installing"
    "deployment.darwin.installed"
    "deployment.config.applying"
    "deployment.config.applied"
    "deployment.completed"
    "deployment.failed"
    
    # Service events
    "service.nats.started"
    "service.nats.stopped"
    "service.nats.health_check"
    "service.monitoring.started"
    "service.monitoring.stopped"
    
    # Operational events
    "backup.started"
    "backup.completed"
    "backup.failed"
    "restore.started"
    "restore.completed"
    "restore.failed"
    "maintenance.update.started"
    "maintenance.update.completed"
    "maintenance.cleanup.performed"
)

# Helper to emit deployment graph events
emit_deployment_event() {
    local event_type="$1"
    local host="$2"
    local data="$3"
    local correlation_id="${4:-$(generate_correlation_id)}"
    local causation_id="${5:-}"
    
    emit_event "$event_type" "$host" "host" "$data" "$correlation_id" "$causation_id"
}

# Export functions for use in other scripts
export -f generate_event_id
export -f generate_correlation_id
export -f emit_event
export -f load_aggregate_events
export -f load_events_by_type
export -f load_events_by_correlation
export -f save_projection
export -f load_projection
export -f emit_deployment_event