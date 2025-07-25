#!/usr/bin/env bash
# Extract hardware inventory from remote Mac before nixos-anywhere installation

set -euo pipefail

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
scp /tmp/extract_mac_info.sh "${USER}@${HOST}:/tmp/" >/dev/null
ssh "${USER}@${HOST}" "chmod +x /tmp/extract_mac_info.sh && /tmp/extract_mac_info.sh" > "$OUTPUT_FILE"

# Clean up
ssh "${USER}@${HOST}" "rm -f /tmp/extract_mac_info.sh"
rm -f /tmp/extract_mac_info.sh

# Create a symlink to latest inventory
ln -sf "hardware_${TIMESTAMP}.json" "${OUTPUT_DIR}/latest.json"

echo "✓ Hardware inventory saved to: $OUTPUT_FILE"
echo "✓ Latest inventory symlinked to: ${OUTPUT_DIR}/latest.json"

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