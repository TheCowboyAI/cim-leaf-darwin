#!/usr/bin/env bash
# Backup and restore procedures for CIM leaf node

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
BACKUP_BASE_DIR="${BACKUP_DIR:-/var/backups/cim-leaf}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Load configuration
if [ -f "leaf.config.json" ]; then
    LEAF_NAME=$(jq -r '.leaf.name' leaf.config.json)
else
    LEAF_NAME="unknown"
fi

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [backup|restore|list] [options]

Commands:
  backup              Create a backup of NATS data and configuration
  restore <backup>    Restore from a specific backup
  list               List available backups

Options:
  -h, --help         Show this help message
  -d, --dir <path>   Override backup directory (default: $BACKUP_BASE_DIR)
  -r, --remote <ssh> Backup to remote location (e.g., user@host:/path)

Examples:
  $SCRIPT_NAME backup
  $SCRIPT_NAME backup --remote backup@nas:/backups/cim
  $SCRIPT_NAME restore 20240124_120000
  $SCRIPT_NAME list
EOF
}

# Parse command line arguments
COMMAND=""
REMOTE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        backup|restore|list)
            COMMAND=$1
            shift
            if [[ "$COMMAND" == "restore" && $# -gt 0 && ! "$1" =~ ^- ]]; then
                RESTORE_TIMESTAMP=$1
                shift
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dir)
            BACKUP_BASE_DIR="$2"
            shift 2
            ;;
        -r|--remote)
            REMOTE="$2"
            shift 2
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

# Create backup directory
BACKUP_DIR="$BACKUP_BASE_DIR/$LEAF_NAME"
mkdir -p "$BACKUP_DIR"

backup() {
    echo "=== CIM Leaf Backup ==="
    echo "Leaf: $LEAF_NAME"
    echo "Timestamp: $TIMESTAMP"
    echo ""
    
    # Create temporary backup directory
    TEMP_BACKUP="/tmp/cim-backup-$TIMESTAMP"
    mkdir -p "$TEMP_BACKUP"
    
    # Stop NATS service to ensure data consistency
    echo "Stopping NATS service..."
    sudo launchctl stop org.nats.server || true
    sleep 2
    
    # Backup NATS data
    echo "Backing up NATS JetStream data..."
    if [ -d "/var/lib/nats" ]; then
        sudo tar -czf "$TEMP_BACKUP/nats-data.tar.gz" -C / var/lib/nats
    else
        echo "Warning: NATS data directory not found"
    fi
    
    # Backup configuration
    echo "Backing up configuration..."
    mkdir -p "$TEMP_BACKUP/config"
    
    # Copy leaf configuration
    [ -f "leaf.config.json" ] && cp "leaf.config.json" "$TEMP_BACKUP/config/"
    
    # Copy nix configurations
    [ -f "flake.nix" ] && cp "flake.nix" "$TEMP_BACKUP/config/"
    [ -f "flake.lock" ] && cp "flake.lock" "$TEMP_BACKUP/config/"
    
    # Copy host configurations
    if [ -d "hosts" ]; then
        cp -r hosts "$TEMP_BACKUP/config/"
    fi
    
    # Copy inventory data
    if [ -d "inventory" ]; then
        cp -r inventory "$TEMP_BACKUP/config/"
    fi
    
    # Backup system information
    echo "Collecting system information..."
    cat > "$TEMP_BACKUP/backup-info.json" << EOF
{
  "leaf_name": "$LEAF_NAME",
  "backup_timestamp": "$TIMESTAMP",
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "system": {
    "hostname": "$(hostname)",
    "darwin_version": "$(sw_vers -productVersion)",
    "nix_version": "$(nix --version)"
  },
  "services": {
    "nats_version": "$(nats-server --version 2>/dev/null || echo 'unknown')"
  }
}
EOF
    
    # Restart NATS service
    echo "Restarting NATS service..."
    sudo launchctl start org.nats.server || true
    
    # Create final backup archive
    BACKUP_FILE="$BACKUP_DIR/backup-$TIMESTAMP.tar.gz"
    echo "Creating backup archive..."
    tar -czf "$BACKUP_FILE" -C "$TEMP_BACKUP" .
    
    # Clean up temporary directory
    rm -rf "$TEMP_BACKUP"
    
    # Handle remote backup if specified
    if [ -n "$REMOTE" ]; then
        echo "Copying backup to remote location: $REMOTE"
        scp "$BACKUP_FILE" "$REMOTE/$LEAF_NAME/"
    fi
    
    echo ""
    echo "✓ Backup completed: $BACKUP_FILE"
    echo "  Size: $(du -h "$BACKUP_FILE" | cut -f1)"
    
    # Cleanup old backups (keep last 7 by default)
    echo ""
    echo "Cleaning up old backups..."
    KEEP_BACKUPS=7
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt "$KEEP_BACKUPS" ]; then
        DELETE_COUNT=$((BACKUP_COUNT - KEEP_BACKUPS))
        ls -1t "$BACKUP_DIR"/backup-*.tar.gz | tail -n "$DELETE_COUNT" | xargs rm -v
    fi
}

restore() {
    if [ -z "${RESTORE_TIMESTAMP:-}" ]; then
        echo "Error: No backup timestamp specified"
        usage
        exit 1
    fi
    
    BACKUP_FILE="$BACKUP_DIR/backup-$RESTORE_TIMESTAMP.tar.gz"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: Backup file not found: $BACKUP_FILE"
        list_backups
        exit 1
    fi
    
    echo "=== CIM Leaf Restore ==="
    echo "Restoring from: $BACKUP_FILE"
    echo ""
    
    # Confirm restore
    read -p "This will overwrite current data. Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Restore cancelled"
        exit 0
    fi
    
    # Create temporary restore directory
    TEMP_RESTORE="/tmp/cim-restore-$RESTORE_TIMESTAMP"
    mkdir -p "$TEMP_RESTORE"
    
    # Extract backup
    echo "Extracting backup..."
    tar -xzf "$BACKUP_FILE" -C "$TEMP_RESTORE"
    
    # Show backup info
    if [ -f "$TEMP_RESTORE/backup-info.json" ]; then
        echo "Backup information:"
        jq . "$TEMP_RESTORE/backup-info.json"
        echo ""
    fi
    
    # Stop NATS service
    echo "Stopping NATS service..."
    sudo launchctl stop org.nats.server || true
    sleep 2
    
    # Restore NATS data
    if [ -f "$TEMP_RESTORE/nats-data.tar.gz" ]; then
        echo "Restoring NATS data..."
        sudo rm -rf /var/lib/nats
        sudo tar -xzf "$TEMP_RESTORE/nats-data.tar.gz" -C /
    fi
    
    # Restore configuration
    if [ -d "$TEMP_RESTORE/config" ]; then
        echo "Restoring configuration..."
        
        # Backup current config first
        [ -f "leaf.config.json" ] && cp "leaf.config.json" "leaf.config.json.bak"
        
        # Restore files
        [ -f "$TEMP_RESTORE/config/leaf.config.json" ] && cp "$TEMP_RESTORE/config/leaf.config.json" .
        [ -d "$TEMP_RESTORE/config/hosts" ] && cp -r "$TEMP_RESTORE/config/hosts" .
        [ -d "$TEMP_RESTORE/config/inventory" ] && cp -r "$TEMP_RESTORE/config/inventory" .
    fi
    
    # Restart NATS service
    echo "Restarting NATS service..."
    sudo launchctl start org.nats.server || true
    
    # Clean up
    rm -rf "$TEMP_RESTORE"
    
    echo ""
    echo "✓ Restore completed from backup $RESTORE_TIMESTAMP"
    echo ""
    echo "Please run a health check:"
    echo "  ./scripts/health_check.sh"
}

list_backups() {
    echo "=== Available Backups ==="
    echo "Directory: $BACKUP_DIR"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo "No backups found"
        return
    fi
    
    echo "Timestamp          Size    Date"
    echo "----------------  ------  ------------------------"
    
    for backup in "$BACKUP_DIR"/backup-*.tar.gz; do
        if [ -f "$backup" ]; then
            TIMESTAMP=$(basename "$backup" | sed 's/backup-\(.*\)\.tar\.gz/\1/')
            SIZE=$(du -h "$backup" | cut -f1)
            DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup" 2>/dev/null || stat -c "%y" "$backup" 2>/dev/null | cut -d' ' -f1,2)
            printf "%-16s  %-6s  %s\n" "$TIMESTAMP" "$SIZE" "$DATE"
        fi
    done
    
    echo ""
    echo "To restore a backup, run:"
    echo "  $SCRIPT_NAME restore <timestamp>"
}

# Execute command
case "$COMMAND" in
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    list)
        list_backups
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac