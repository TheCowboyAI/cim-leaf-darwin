#!/usr/bin/env bash
# Extract hardware inventory from remote Mac before nixos-anywhere installation

set -euo pipefail

# Source event store functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/event_store.sh"

# Check if hostname is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <hostname_or_ip> [username]"
    echo "Example: $0 192.168.1.100 admin"
    exit 1
fi

HOST="$1"
USER="${2:-admin}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="inventory/${HOST}"
OUTPUT_FILE="${OUTPUT_DIR}/hardware_${TIMESTAMP}.json"

# Create inventory directory
mkdir -p "$OUTPUT_DIR"

echo "Extracting hardware inventory from ${USER}@${HOST}..."

# Start correlation for this inventory extraction
CORRELATION_ID=$(generate_correlation_id)

# Emit extraction started event
emit_deployment_event "inventory.extraction.started" "$HOST" \
    "$(jq -n --arg user "$USER" --arg host "$HOST" --arg timestamp "$TIMESTAMP" \
    '{user: $user, host: $host, timestamp: $timestamp}')" \
    "$CORRELATION_ID"

# Create temporary script to run on remote
cat > /tmp/extract_mac_info.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail

# Function to safely get system profiler data
get_sp_data() {
    local data_type="$1"
    system_profiler -json "$data_type" 2>/dev/null || echo "{}"
}

# Collect all hardware information
{
    echo "{"
    
    # Basic system info
    echo '"system_info": {'
    echo "  \"hostname\": \"$(scutil --get LocalHostName)\","
    echo "  \"computer_name\": \"$(scutil --get ComputerName)\","
    echo "  \"model\": \"$(sysctl -n hw.model)\","
    echo "  \"serial_number\": \"$(system_profiler SPHardwareDataType | grep 'Serial Number' | awk '{print $4}')\","
    echo "  \"architecture\": \"$(uname -m)\","
    echo "  \"kernel\": \"$(uname -r)\","
    echo "  \"macos_version\": \"$(sw_vers -productVersion)\","
    echo "  \"macos_build\": \"$(sw_vers -buildVersion)\""
    echo "},"
    
    # Hardware details
    echo '"hardware": {'
    echo "  \"cpu_type\": \"$(sysctl -n machdep.cpu.brand_string)\","
    echo "  \"cpu_cores\": $(sysctl -n hw.ncpu),"
    echo "  \"cpu_threads\": $(sysctl -n hw.logicalcpu),"
    echo "  \"memory_gb\": $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )),"
    echo "  \"memory_bytes\": $(sysctl -n hw.memsize)"
    echo "},"
    
    # Disk information
    echo '"disks": ['
    diskutil list -plist | plutil -convert json -o - - | \
        jq -r '.AllDisksAndPartitions[] | 
        {
            device: .DeviceIdentifier,
            size: .Size,
            content: .Content,
            internal: .Internal,
            protocol: .IORegistryEntryName
        } | @json' | \
        paste -sd "," -
    echo "],"
    
    # Network interfaces
    echo '"network_interfaces": ['
    networksetup -listallhardwareports | \
        awk '/Hardware Port:/{port=$3$4$5} /Device:/{print "{\"port\": \"" port "\", \"device\": \"" $2 "\"},"}' | \
        sed '$ s/,$//'
    echo "],"
    
    # Full system profiler data
    echo '"system_profiler": {'
    echo "  \"SPHardwareDataType\": $(get_sp_data SPHardwareDataType),"
    echo "  \"SPMemoryDataType\": $(get_sp_data SPMemoryDataType),"
    echo "  \"SPStorageDataType\": $(get_sp_data SPStorageDataType),"
    echo "  \"SPNetworkDataType\": $(get_sp_data SPNetworkDataType),"
    echo "  \"SPThunderboltDataType\": $(get_sp_data SPThunderboltDataType),"
    echo "  \"SPUSBDataType\": $(get_sp_data SPUSBDataType)"
    echo "},"
    
    # Timestamp
    echo '"extracted_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"'
    
    echo "}"
} | jq '.'
SCRIPT

# Copy and execute script on remote
if scp /tmp/extract_mac_info.sh "${USER}@${HOST}:/tmp/" >/dev/null 2>&1; then
    if ssh "${USER}@${HOST}" "chmod +x /tmp/extract_mac_info.sh && /tmp/extract_mac_info.sh" > "$OUTPUT_FILE" 2>/dev/null; then
        # Extraction succeeded
        INVENTORY_DATA=$(cat "$OUTPUT_FILE")
        
        # Emit hardware discovered event
        emit_deployment_event "inventory.hardware.discovered" "$HOST" \
            "$INVENTORY_DATA" \
            "$CORRELATION_ID"
        
        # Emit extraction completed event
        emit_deployment_event "inventory.extraction.completed" "$HOST" \
            "$(jq -n --arg file "$OUTPUT_FILE" --arg size "$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE")" \
            '{output_file: $file, size_bytes: $size}')" \
            "$CORRELATION_ID"
        
        # Clean up
        ssh "${USER}@${HOST}" "rm -f /tmp/extract_mac_info.sh" 2>/dev/null || true
        rm -f /tmp/extract_mac_info.sh
        
        # Create a symlink to latest inventory
        ln -sf "hardware_${TIMESTAMP}.json" "${OUTPUT_DIR}/latest.json"
        
        echo "✓ Hardware inventory saved to: $OUTPUT_FILE"
        echo "✓ Latest inventory symlinked to: ${OUTPUT_DIR}/latest.json"
    else
        # Extraction failed
        ERROR_MSG="Failed to execute inventory script on remote host"
        emit_deployment_event "inventory.extraction.failed" "$HOST" \
            "$(jq -n --arg error "$ERROR_MSG" '{error: $error}')" \
            "$CORRELATION_ID"
        
        echo "✗ $ERROR_MSG" >&2
        exit 1
    fi
else
    # SCP failed
    ERROR_MSG="Failed to copy script to remote host"
    emit_deployment_event "inventory.extraction.failed" "$HOST" \
        "$(jq -n --arg error "$ERROR_MSG" '{error: $error}')" \
        "$CORRELATION_ID"
    
    echo "✗ $ERROR_MSG" >&2
    exit 1
fi

# Display summary
echo ""
echo "Summary:"
jq -r '
    "  Hostname: \(.system_info.hostname)",
    "  Model: \(.system_info.model)",
    "  Serial: \(.system_info.serial_number)",
    "  CPU: \(.hardware.cpu_type)",
    "  Memory: \(.hardware.memory_gb) GB",
    "  Disks: \(.disks | length)",
    "  macOS: \(.system_info.macos_version) (\(.system_info.macos_build))"
' "$OUTPUT_FILE"