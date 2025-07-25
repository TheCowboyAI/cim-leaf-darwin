# Hardware module that applies optimizations based on detected hardware
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.optimization;
in
{
  options.hardware.optimization = {
    enable = mkEnableOption "hardware-based optimizations";
    
    profile = mkOption {
      type = types.enum [ "auto" "performance" "balanced" "powersave" ];
      default = "auto";
      description = "Performance profile to apply";
    };
  };

  config = mkIf cfg.enable {
    # Auto-detect and apply optimizations
    nix.settings = mkMerge [
      {
        # Base settings
        sandbox = true;
        trusted-users = [ "@admin" ];
      }
      
      # Performance settings based on hardware
      (mkIf (cfg.profile == "performance") {
        max-jobs = "auto";
        cores = 0;
        max-substitution-jobs = 16;
        http-connections = 50;
      })
    ];
    
    # System-wide performance tuning
    system.defaults = mkMerge [
      {
        # Finder performance
        NSGlobalDomain = {
          NSAutomaticWindowAnimationsEnabled = cfg.profile != "performance";
          NSWindowResizeTime = if cfg.profile == "performance" then 0.001 else null;
        };
        
        # Dock performance
        dock = {
          autohide-delay = if cfg.profile == "performance" then 0.0 else null;
          autohide-time-modifier = if cfg.profile == "performance" then 0.0 else null;
        };
      }
    ];
    
    # Power management based on profile
    system.defaults.pmset = mkMerge [
      (mkIf (cfg.profile == "performance") {
        AC = {
          "System Performance" = 3;
          "Processor Speed" = 3;
          diskSleep = 0;
          sleep = 0;
          displaySleep = 0;
        };
      })
      
      (mkIf (cfg.profile == "powersave") {
        AC = {
          "System Performance" = 1;
          diskSleep = 10;
          sleep = 30;
          displaySleep = 15;
        };
      })
    ];
  };
}