#!/usr/bin/env bash
# Maintenance operations for CIM leaf nodes

set -euo pipefail

usage() {
    cat << EOF
CIM Leaf Maintenance Script

Usage: $0 <command> [options]

Commands:
  update        Update nix flakes and rebuild
  rotate-logs   Force log rotation
  cleanup       Clean old data and logs
  compact       Compact NATS JetStream storage
  status        Show comprehensive system status

Options:
  -h, --help    Show this help message
  -y, --yes     Skip confirmation prompts

Examples:
  $0 update
  $0 cleanup --yes
  $0 compact
EOF
}

# Parse arguments
COMMAND=""
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        update|rotate-logs|cleanup|compact|status)
            COMMAND=$1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
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

# Load configuration
if [ -f "leaf.config.json" ]; then
    LEAF_NAME=$(jq -r '.leaf.name' leaf.config.json)
else
    LEAF_NAME="unknown"
fi

confirm() {
    if [ "$SKIP_CONFIRM" = true ]; then
        return 0
    fi
    
    read -p "$1 (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

update_system() {
    echo "=== System Update ==="
    echo "Updating flake inputs..."
    
    # Update flake
    nix flake update
    
    echo "Building new configuration..."
    darwin-rebuild build --flake .
    
    if confirm "Apply new configuration?"; then
        echo "Applying configuration..."
        darwin-rebuild switch --flake .
        
        echo ""
        echo "✓ System updated successfully"
        echo ""
        echo "Run health check to verify:"
        echo "  ./scripts/health_check.sh"
    else
        echo "Update cancelled"
    fi
}

rotate_logs() {
    echo "=== Log Rotation ==="
    
    # Trigger log rotation daemon
    sudo launchctl kickstart -k system/org.cim.log-rotation
    
    echo "✓ Log rotation triggered"
    
    # Show log sizes
    echo ""
    echo "Current log sizes:"
    find /var/log -name "*.log" -type f 2>/dev/null | while read -r log; do
        size=$(du -h "$log" 2>/dev/null | cut -f1)
        echo "  $log: $size"
    done | sort -k2 -hr | head -10
}

cleanup_system() {
    echo "=== System Cleanup ==="
    
    # Calculate space before cleanup
    BEFORE_SPACE=$(df -h / | awk 'NR==2 {print $4}')
    
    echo "Cleaning old Nix store paths..."
    nix-collect-garbage -d
    
    echo "Cleaning old logs..."
    find /var/log -name "*.log.*" -mtime +30 -delete 2>/dev/null || true
    
    echo "Cleaning temporary files..."
    find /tmp -type f -mtime +7 -delete 2>/dev/null || true
    
    # Calculate space after cleanup
    AFTER_SPACE=$(df -h / | awk 'NR==2 {print $4}')
    
    echo ""
    echo "✓ Cleanup completed"
    echo "  Disk space before: $BEFORE_SPACE"
    echo "  Disk space after: $AFTER_SPACE"
}

compact_jetstream() {
    echo "=== JetStream Compaction ==="
    
    if ! curl -s http://localhost:8222/healthz &>/dev/null; then
        echo "Error: NATS is not running"
        exit 1
    fi
    
    echo "Current JetStream info:"
    ${pkgs.natscli}/bin/nats server report jetstream
    
    if confirm "Compact all JetStream file stores?"; then
        # Get all streams
        STREAMS=$(${pkgs.natscli}/bin/nats stream list -j | jq -r '.streams[].config.name')
        
        for stream in $STREAMS; do
            echo "Compacting stream: $stream"
            ${pkgs.natscli}/bin/nats stream compact "$stream" -f
        done
        
        echo ""
        echo "✓ JetStream compaction completed"
    else
        echo "Compaction cancelled"
    fi
}

show_status() {
    echo "=== CIM Leaf Status Report ==="
    echo "Leaf: $LEAF_NAME"
    echo "Time: $(date)"
    echo ""
    
    # System info
    echo "=== System Information ==="
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime)"
    echo "Darwin: $(sw_vers -productVersion)"
    echo "Nix: $(nix --version)"
    echo ""
    
    # Service status
    echo "=== Service Status ==="
    for service in nats prometheus node-exporter grafana; do
        if sudo launchctl list | grep -q "org.*$service"; then
            PID=$(sudo launchctl list | grep "org.*$service" | awk '{print $1}')
            if [ "$PID" != "-" ]; then
                echo "✓ $service: Running (PID: $PID)"
            else
                echo "✗ $service: Not running"
            fi
        else
            echo "- $service: Not configured"
        fi
    done
    echo ""
    
    # NATS detailed status
    if curl -s http://localhost:8222/healthz &>/dev/null; then
        echo "=== NATS Status ==="
        VARZ=$(curl -s http://localhost:8222/varz)
        echo "Version: $(echo "$VARZ" | jq -r '.version')"
        echo "Uptime: $(echo "$VARZ" | jq -r '.uptime')"
        echo "Connections: $(echo "$VARZ" | jq -r '.connections')"
        echo "Messages In: $(echo "$VARZ" | jq -r '.in_msgs')"
        echo "Messages Out: $(echo "$VARZ" | jq -r '.out_msgs')"
        echo "Data In: $(echo "$VARZ" | jq -r '.in_bytes' | numfmt --to=iec)"
        echo "Data Out: $(echo "$VARZ" | jq -r '.out_bytes' | numfmt --to=iec)"
        
        # JetStream status
        JSZ=$(curl -s http://localhost:8222/jsz)
        if [ $? -eq 0 ]; then
            echo ""
            echo "JetStream:"
            echo "  Memory: $(echo "$JSZ" | jq -r '.memory' | numfmt --to=iec)"
            echo "  Storage: $(echo "$JSZ" | jq -r '.storage' | numfmt --to=iec)"
            echo "  Streams: $(echo "$JSZ" | jq -r '.streams')"
            echo "  Consumers: $(echo "$JSZ" | jq -r '.consumers')"
        fi
    fi
    echo ""
    
    # Disk usage
    echo "=== Disk Usage ==="
    df -h / | grep -v Filesystem
    echo ""
    echo "NATS data:"
    du -sh /var/lib/nats 2>/dev/null || echo "  Not found"
    echo "Logs:"
    du -sh /var/log 2>/dev/null || echo "  Not found"
    echo ""
    
    # Recent errors
    echo "=== Recent Errors (last 10) ==="
    find /var/log -name "*.log" -type f 2>/dev/null | while read -r log; do
        grep -i "error\|fail\|critical" "$log" 2>/dev/null | tail -5
    done | tail -10 || echo "No recent errors found"
}

# Execute command
case "$COMMAND" in
    update)
        update_system
        ;;
    rotate-logs)
        rotate_logs
        ;;
    cleanup)
        cleanup_system
        ;;
    compact)
        compact_jetstream
        ;;
    status)
        show_status
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac