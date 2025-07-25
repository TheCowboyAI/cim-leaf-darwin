{ config, pkgs, ... }:

{
  # System packages
  environment.systemPackages = with pkgs; [
    # Core tools
    coreutils
    gnused
    gnugrep
    gawk
    findutils
    
    # Development essentials
    git
    vim
    tmux
    ripgrep
    fd
    jq
    yq
    tree
    htop
    
    # Nix tools
    nix-index
    nixpkgs-fmt
    nil
    
    # Build tools
    gnumake
    cmake
    pkg-config
    
    # Rust toolchain
    rustup
    
    # NATS server
    nats-server
    
    # Network tools
    curl
    wget
    netcat
    
    # Archive tools
    unzip
    p7zip
  ];

  # Auto upgrade nix package and daemon
  services.nix-daemon.enable = true;
  nix = {
    package = pkgs.nix;
    
    settings = {
      # Enable flakes
      experimental-features = "nix-command flakes";
      
      # Build options
      max-jobs = "auto";
      cores = 0; # Use all available cores
      
      # Trusted users
      trusted-users = [ "@admin" ];
      
      # Substituters
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    
    # Garbage collection
    gc = {
      automatic = true;
      interval = { Hour = 3; Minute = 0; };
      options = "--delete-older-than 30d";
    };
  };

  # System defaults
  system = {
    stateVersion = 4;
    
    defaults = {
      # Finder
      finder = {
        AppleShowAllExtensions = true;
        FXPreferredViewStyle = "clmv"; # Column view
        ShowPathbar = true;
        ShowStatusBar = true;
      };
      
      # Dock
      dock = {
        autohide = true;
        orientation = "bottom";
        show-recents = false;
        tilesize = 48;
        minimize-to-application = true;
      };
      
      # Global
      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleKeyboardUIMode = 3; # Full keyboard access
        ApplePressAndHoldEnabled = false;
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
      };
      
      # Screenshots
      screencapture.location = "~/Desktop";
      
      # Disable Spotlight indexing for /nix
      ".Spotlight-V100".VolumeConfiguration = {
        "/nix" = {
          enabled = false;
        };
      };
    };
  };

  # Shell configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableBashCompletion = true;
  };

  # Security
  security.pam.enableSudoTouchIdAuth = true;

  # Fonts
  fonts = {
    fontDir.enable = true;
    fonts = with pkgs; [
      (nerdfonts.override { fonts = [ "JetBrainsMono" "FiraCode" ]; })
    ];
  };

  # Enable Touch ID for sudo
  environment.etc."pam.d/sudo_local" = {
    text = ''
      auth       sufficient     pam_tid.so
    '';
  };

  # System-wide shell aliases
  environment.shellAliases = {
    ll = "ls -la";
    la = "ls -A";
    l = "ls -CF";
    rebuild = "darwin-rebuild switch --flake ~/cim-leaf-darwin";
    update = "cd ~/cim-leaf-darwin && nix flake update && darwin-rebuild switch --flake .";
  };

  # Documentation
  documentation = {
    enable = true;
    doc.enable = true;
    info.enable = true;
    man.enable = true;
  };
}