{ config, lib, pkgs, leafConfig, ... }:

let
  isProd = leafConfig.leaf.environment == "prod";
in
{
  # Security hardening for CIM leaf nodes
  
  # System security settings
  security = {
    # Enable sudo with Touch ID
    pam.enableSudoTouchIdAuth = true;
    
    # Require password for sudo in production
    sudo = lib.mkIf isProd {
      wheelNeedsPassword = true;
      extraConfig = ''
        # Require password for all sudo commands
        Defaults    env_reset
        Defaults    timestamp_timeout=0
        Defaults    requiretty
        
        # Log all sudo commands
        Defaults    logfile="/var/log/sudo.log"
        Defaults    log_input
        Defaults    log_output
      '';
    };
  };
  
  # Network security
  networking = {
    # Basic firewall rules (if pf is enabled)
    # Note: macOS uses pf (packet filter) instead of iptables
    knownNetworkServices = [ "Wi-Fi" "Ethernet" ];
  };
  
  # File integrity monitoring
  launchd.daemons.file-integrity = lib.mkIf isProd {
    enable = true;
    config = {
      Label = "org.cim.file-integrity";
      ProgramArguments = [
        "${pkgs.writeShellScript "check-integrity" ''
          #!/bin/bash
          # Check critical file modifications
          
          WATCH_PATHS=(
            "/etc/nats"
            "/var/lib/nats"
            "/nix/store"
          )
          
          for path in "''${WATCH_PATHS[@]}"; do
            if [ -d "$path" ]; then
              find "$path" -type f -mtime -1 -exec ls -la {} \; >> /var/log/file-changes.log
            fi
          done
        ''}"
      ];
      StartInterval = 3600; # Run every hour
      StandardErrorPath = "/var/log/file-integrity-error.log";
      StandardOutPath = "/var/log/file-integrity.log";
    };
  };
  
  # NATS security configuration
  system.activationScripts.nats-security = {
    text = ''
      # Generate NATS server config with security settings
      mkdir -p /etc/nats
      
      cat > /etc/nats/server.conf << 'EOF'
      # NATS Server Security Configuration
      
      # Monitoring access control
      http: localhost:8222
      
      # Connection limits
      max_connections: 1000
      max_control_line: 4096
      max_payload: 8MB
      
      # Write deadline
      write_deadline: "10s"
      
      # Authorization
      authorization {
        # Default permissions
        default_permissions = {
          publish = {
            deny = [">"]
          }
          subscribe = {
            deny = [">"]
          }
        }
        
        # Service account
        SERVICES = {
          publish = {
            allow = ["cim.>"]
          }
          subscribe = {
            allow = ["cim.>", "_INBOX.>"]
          }
        }
        
        # Monitoring account
        MONITOR = {
          publish = {
            deny = [">"]
          }
          subscribe = {
            allow = ["$SYS.>"]
          }
        }
        
        # Users
        users = [
          { user: service, password: "$SERVICE_PASSWORD", permissions: $SERVICES }
          { user: monitor, password: "$MONITOR_PASSWORD", permissions: $MONITOR }
        ]
      }
      
      # TLS Configuration (if certificates are available)
      # tls {
      #   cert_file: "/etc/nats/certs/server.crt"
      #   key_file: "/etc/nats/certs/server.key"
      #   ca_file: "/etc/nats/certs/ca.crt"
      #   verify: true
      # }
      
      # Logging
      debug: false
      trace: false
      logtime: true
      log_file: "/var/log/nats/server.log"
      
      # Clustering security
      cluster {
        name: ${leafConfig.nats.cluster_name}
        
        # Cluster authorization
        authorization {
          user: cluster
          password: "$CLUSTER_PASSWORD"
          timeout: 2
        }
      }
      EOF
      
      # Set proper permissions
      chmod 600 /etc/nats/server.conf
    '';
  };
  
  # Log rotation and management
  launchd.daemons.log-rotation = {
    enable = true;
    config = {
      Label = "org.cim.log-rotation";
      ProgramArguments = [
        "${pkgs.writeShellScript "rotate-logs" ''
          #!/bin/bash
          # Rotate logs for all CIM services
          
          LOGS=(
            "/var/log/nats/*.log"
            "/var/log/prometheus/*.log"
            "/var/log/grafana/*.log"
            "/var/log/sudo.log"
            "/var/log/file-changes.log"
          )
          
          for logpattern in "''${LOGS[@]}"; do
            for logfile in $logpattern; do
              if [ -f "$logfile" ] && [ -s "$logfile" ]; then
                # Rotate if larger than 100MB
                size=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null)
                if [ "$size" -gt 104857600 ]; then
                  mv "$logfile" "$logfile.$(date +%Y%m%d_%H%M%S)"
                  touch "$logfile"
                  
                  # Keep only last 5 rotated logs
                  ls -t "$logfile".* 2>/dev/null | tail -n +6 | xargs rm -f
                fi
              fi
            done
          done
        ''}"
      ];
      StartInterval = 86400; # Daily
    };
  };
  
  # System audit logging
  system.activationScripts.audit-setup = lib.mkIf isProd {
    text = ''
      # Enable audit logging for security events
      mkdir -p /var/log/audit
      
      # Configure audit policy
      cat > /etc/security/audit_control << 'EOF'
      # Audit configuration
      dir:/var/log/audit
      flags:lo,aa,ad,fd,fw,fc,fm
      minfree:20
      naflags:lo,aa
      policy:cnt,argv
      filesz:2M
      expire-after:10M
      EOF
      
      # Start audit daemon
      audit -i || true
    '';
  };
  
  # Environment security
  environment.variables = {
    # Disable core dumps in production
    COREDUMP = lib.mkIf isProd "0";
    
    # Security headers for any HTTP services
    SECURE_HEADERS = lib.mkIf isProd "true";
  };
  
  # Package security updates
  system.activationScripts.security-updates = {
    text = ''
      echo "Checking for security updates..."
      
      # Log package versions for security tracking
      nix-store -q --tree /run/current-system | head -50 > /var/log/nix-packages.log
      
      # Note: Actual updates are handled by nix flake update
    '';
  };
  
  # SSH hardening (if SSH is enabled)
  programs.ssh.extraConfig = lib.mkIf isProd ''
    # SSH client security settings
    Host *
      PasswordAuthentication no
      ChallengeResponseAuthentication no
      HashKnownHosts yes
      SendEnv LANG LC_*
      StrictHostKeyChecking ask
  '';
  
  # Additional security packages
  environment.systemPackages = with pkgs; [
    # Security tools
    lynis          # Security auditing
    fail2ban       # Intrusion prevention
    rkhunter       # Rootkit hunter
  ] ++ lib.optionals isProd [
    # Production-only security tools
    aide           # Intrusion detection
    chkrootkit     # Rootkit checker
  ];
}