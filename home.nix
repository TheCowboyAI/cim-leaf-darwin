{ config, pkgs, ... }:

{
  # Home Manager version
  home.stateVersion = "24.05";

  # User packages
  home.packages = with pkgs; [
    # NATS tools
    natscli
    nats-top
    
    # Development tools
    helix
    lazygit
    gh
    direnv
    
    # Rust tools (additional to system)
    cargo-edit
    cargo-watch
    cargo-nextest
    bacon
    
    # System monitoring
    htop
    btop
    
    # Productivity
    bat
    eza
    zoxide
    fzf
    starship
  ];

  # Git configuration
  programs.git = {
    enable = true;
    userName = "CIM Developer"; # Update with actual name
    userEmail = "dev@cim-leaf.local"; # Update with actual email
    
    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      
      core = {
        editor = "hx";
        autocrlf = "input";
      };
      
      diff = {
        colorMoved = "default";
      };
      
      merge = {
        conflictstyle = "diff3";
      };
    };
    
    aliases = {
      st = "status -sb";
      co = "checkout";
      br = "branch";
      ci = "commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      visual = "!gitk";
      lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
    };
  };

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    shellAliases = {
      # Navigation
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      
      # Better defaults
      ls = "eza";
      ll = "eza -la";
      la = "eza -a";
      lt = "eza --tree";
      cat = "bat";
      
      # NATS shortcuts
      nats-status = "curl -s http://localhost:8222/varz | jq";
      nats-health = "curl -s http://localhost:8222/healthz";
      
      # Nix shortcuts
      ns = "nix-shell";
      nb = "nix build";
      nr = "darwin-rebuild switch --flake ~/cim-leaf-darwin";
      
      # Development
      c = "cargo";
      cr = "cargo run";
      ct = "cargo test";
      cc = "cargo check";
      cb = "cargo build";
      cw = "cargo watch -x check";
      
      # CIM specific
      cim-logs = "tail -f /var/log/nats/*.log";
      cim-status = "sudo launchctl list | grep nats";
      cim-restart = "sudo launchctl kickstart -k system/org.nixos.nats";
    };
    
    initExtra = ''
      # Starship prompt
      eval "$(starship init zsh)"
      
      # Zoxide
      eval "$(zoxide init zsh)"
      
      # FZF
      source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      source ${pkgs.fzf}/share/fzf/completion.zsh
      
      # Direnv
      eval "$(direnv hook zsh)"
      
      # Set EDITOR
      export EDITOR=hx
      export VISUAL=hx
      
      # Rust environment
      export RUST_BACKTRACE=1
    '';
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      format = ''
        [┌───────────────────>](bold green)
        [│](bold green) $directory$git_branch$git_status$rust$nix_shell
        [└─>](bold green) 
      '';
      
      directory = {
        style = "bold cyan";
        truncation_length = 3;
        truncate_to_repo = false;
      };
      
      git_branch = {
        style = "bold purple";
        symbol = " ";
      };
      
      git_status = {
        style = "bold red";
        ahead = "⇡$count";
        diverged = "⇕⇡$ahead_count⇣$behind_count";
        behind = "⇣$count";
      };
      
      rust = {
        style = "bold red";
        symbol = " ";
      };
      
      nix_shell = {
        style = "bold blue";
        symbol = " ";
      };
    };
  };

  # Helix editor
  programs.helix = {
    enable = true;
    settings = {
      theme = "onedark";
      
      editor = {
        line-number = "relative";
        mouse = false;
        rulers = [80 120];
        bufferline = "always";
        color-modes = true;
        true-color = true;
        
        cursor-shape = {
          insert = "bar";
          normal = "block";
          select = "underline";
        };
        
        indent-guides = {
          render = true;
          rainbow-option = "dim";
        };
        
        lsp = {
          display-messages = true;
          display-inlay-hints = true;
        };
        
        statusline = {
          left = ["mode" "spinner" "version-control" "file-name"];
          center = ["file-type"];
          right = ["diagnostics" "selections" "position" "file-encoding"];
        };
      };
      
      keys.normal = {
        space.space = "file_picker";
        space.w = ":w";
        space.q = ":q";
      };
    };
    
    languages = {
      language = [
        {
          name = "rust";
          auto-format = true;
          formatter = { command = "rustfmt"; };
        }
        {
          name = "nix";
          auto-format = true;
          formatter = { command = "nixpkgs-fmt"; };
        }
      ];
    };
  };

  # Direnv
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # SSH
  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host *
        AddKeysToAgent yes
        UseKeychain yes
    '';
  };

  # Create common directories
  home.file = {
    ".config/.keep".text = "";
    "Development/.keep".text = "";
    "Development/cim/.keep".text = "";
  };
}