#!/usr/bin/env bash
# Convert JSON inventory to Nix configuration

set -euo pipefail

# Check if inventory file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <inventory_json_file> [output_nix_file]"
    echo "Example: $0 inventory/mac-1/latest.json hosts/mac-1/hardware.nix"
    exit 1
fi

INVENTORY_FILE="$1"
OUTPUT_FILE="${2:-/dev/stdout}"

# Check if inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
    echo "Error: Inventory file not found: $INVENTORY_FILE" >&2
    exit 1
fi

# Convert JSON to Nix using jq
jq -r '
# Helper to safely convert values
def safe_string: if . == null then "null" else tostring | @json end;
def safe_number: if . == null then "null" else tostring end;

"# Hardware configuration from inventory
# Generated from: \(input_filename)
# Extracted at: \(.extracted_at)
{ lib, ... }:

{
  # System identification
  system = {
    hostname = \(.system_info.hostname | safe_string);
    computerName = \(.system_info.computer_name | safe_string);
    model = \(.system_info.model | safe_string);
    serialNumber = \(.system_info.serial_number | safe_string);
  };

  # Hardware specifications
  hardware = {
    # CPU information
    cpu = {
      type = \(.hardware.cpu_type | safe_string);
      cores = \(.hardware.cpu_cores | safe_number);
      threads = \(.hardware.cpu_threads | safe_number);
    };
    
    # Memory
    memory = {
      sizeGB = \(.hardware.memory_gb | safe_number);
      sizeBytes = \(.hardware.memory_bytes | safe_number);
    };
    
    # Architecture
    arch = \(.system_info.architecture | safe_string);
  };

  # Operating system
  os = {
    version = \(.system_info.macos_version | safe_string);
    build = \(.system_info.macos_build | safe_string);
    kernel = \(.system_info.kernel | safe_string);
  };

  # Disk configuration
  disks = [" +
    (.disks | map("
    {
      device = \(.device | safe_string);
      size = \(.size | safe_number);
      content = \(.content | safe_string);
      internal = \(.internal | tostring);
      protocol = \(.protocol | safe_string);
    }") | join("")) + "
  ];

  # Network interfaces
  networking.interfaces = {" +
    (.network_interfaces | map("
    \(.device | gsub("[^a-zA-Z0-9]"; "_")) = {
      device = \(.device | safe_string);
      port = \(.port | safe_string);
    };") | join("")) + "
  };

  # Performance tuning based on hardware
  performance = {
    # Memory pressure settings based on available RAM
    memoryPressure = {
      threshold = if \(.hardware.memory_gb) >= 64 then 90
                 else if \(.hardware.memory_gb) >= 32 then 85
                 else 80;
    };
    
    # CPU settings based on core count
    maxConcurrency = if \(.hardware.cpu_cores) >= 16 then \"high\"
                    else if \(.hardware.cpu_cores) >= 8 then \"medium\"
                    else \"low\";
    
    # NATS settings based on hardware
    nats = {
      maxConnections = if \(.hardware.cpu_cores) >= 16 then 10000
                      else if \(.hardware.cpu_cores) >= 8 then 5000
                      else 1000;
      
      maxPending = if \(.hardware.memory_gb) >= 64 then \"2GB\"
                  else if \(.hardware.memory_gb) >= 32 then \"1GB\"
                  else \"512MB\";
    };
  };

  # Storage recommendations
  storage = {
    # JetStream storage based on available disk
    jetstream = {
      maxFileStore = if \((.disks | map(select(.internal == true) | .size) | add // 0) / 1024 / 1024 / 1024) >= 1000 then \"500GB\"
                    else if \((.disks | map(select(.internal == true) | .size) | add // 0) / 1024 / 1024 / 1024) >= 500 then \"200GB\"
                    else \"100GB\";
      
      maxMemoryStore = if \(.hardware.memory_gb) >= 64 then \"16GB\"
                      else if \(.hardware.memory_gb) >= 32 then \"8GB\"
                      else \"4GB\";
    };
    
    # Backup storage
    backup = {
      retentionDays = if \((.disks | map(select(.internal == true) | .size) | add // 0) / 1024 / 1024 / 1024) >= 1000 then 90
                     else if \((.disks | map(select(.internal == true) | .size) | add // 0) / 1024 / 1024 / 1024) >= 500 then 30
                     else 14;
    };
  };

  # Monitoring settings based on environment
  monitoring = {
    # Higher retention for systems with more storage
    prometheus.retention = if \((.disks | map(select(.internal == true) | .size) | add // 0) / 1024 / 1024 / 1024) >= 1000 then \"90d\"
                          else if \((.disks | map(select(.internal == true) | .size) | add // 0) / 1024 / 1024 / 1024) >= 500 then \"30d\"
                          else \"7d\";
  };
}"
' "$INVENTORY_FILE" > "$OUTPUT_FILE"

echo "✓ Nix configuration generated: $OUTPUT_FILE"