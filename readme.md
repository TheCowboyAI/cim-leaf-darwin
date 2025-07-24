# Quick-start guide: turning a brand-new Mac Studio into a CIM leaf node

**Main takeaway** – Install the multi-user Nix package manager, bootstrap `nix-win` + Home-Manager with the flake below, and use Colima to run an isolated Linux VM that hosts the NATS + JetStream container required by a “cim-leaf”. Everything (system tweaks, packages, VM, container) is declared in a single `flake.nix`, making every future leaf (`cim-leaf-*`) reproducible.

## 1. One-time preparation (out-of-the-box Mac Studio)

1. Create an admin account and open Terminal.  
2. Install the Determinate Systems multi-user Nix daemon (adds Rosetta-ready ARM binaries, sets experimental CLI flags and enables flakes)  

```bash
sh <(curl -L https://install.determinate.systems/nix) \
     --extra-conf 'experimental-features = nix-command flakes'        \
     --daemon                                                         \
     --yes
```
(The official script works too, but Determinate gives better Apple-silicon defaults[1][2][3].)

3. Close Terminal, open a **new** shell so that `/nix/var/nix/profiles/default/bin` is on `$PATH`.

## 2. Bootstrap `nix-darwin`

```bash
# grab template and build immediately
git clone https://github.com/thecowboyai/alchemist.git cim-leaf-darwin
cd cim-leaf-darwin
darwin-rebuild switch --flake .#"$(scutil --get LocalHostName)"
```

`darwin-rebuild` comes from the channel that `nix-darwin` adds during the first evaluation; the command will:

* download the inputs pinned in the flake,
* build `/run/current-system`,
* activate all macOS defaults, launchd daemons and Home-Manager user files in one transaction[4].

## 3. What the provided flake does

```nix
{
  description = "cim-leaf-darwin template";

  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url    = "github:numtide/flake-utils";
    darwin.url         = "github:nix-darwin/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url   = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        username = "YOURUSER";        # adjust or autogenerate
      in {
        darwinConfigurations."${system}" = darwin.lib.darwinSystem {
          inherit system;
          modules = [
            ./darwin.nix               # core macOS settings
            home-manager.darwinModules.home-manager
            {
              users.users.${username}.home = "/Users/${username}";
              home-manager.useGlobalPkgs    = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} = import ./home.nix;

              # --- Homebrew (for Colima VM helper) -------------------------
              homebrew = {
                enable = true;
                brews  = [ "colima" "docker" ];   # tiny CLI only
                taps   = [ "homebrew/cask" ];
              };

              # --- Colima VM + Docker context -----------------------------
              launchd.daemons.colima = {
                enable    = true;
                config    = {
                  ProgramArguments = [ "${pkgs.colima}/bin/colima" "start" "--runtime" "docker" "--memory" "4" "--cpu" "4" ];
                  KeepAlive        = true;
                  RunAtLoad        = true;
                  EnvironmentVariables = { PATH = pkgs.lib.makeBinPath [ pkgs.colima pkgs.docker ]; };
                  StandardErrorPath  = "/tmp/colima.err";
                  StandardOutPath    = "/tmp/colima.out";
                };
              };

              # point docker CLI at Colima socket
              environment.variables.DOCKER_HOST = "unix://$HOME/.colima/default/docker.sock";
            }
          ];
        };
      });
}
```

### darwin.nix (macOS layer)

* Enables automatic software updates, basic security hardening, and CLI developer tools.
* Installs `nix-index`, `ripgrep`, `git`, `jq`, `tmux`, Rust tool-chain.
* Sets Z-shell as default, adds completion, and turns off Spotlight indexing on `/nix`.

### home.nix (user layer)

```nix
{ pkgs, ... }: {
  home.stateVersion = "24.05";
  home.packages = with pkgs; [ nats-top helix ];

  programs.git = { enable = true; userName = "Your Name"; userEmail = "[email protected]"; };

  # convenience aliases
  home.shellAliases = {
    d  = "docker";
    nr = "darwin-rebuild switch --flake ~/cim-leaf-darwin";
  };
}
```

### NATS + JetStream container definition

Create `docker-compose.yaml` inside the repo:

```yaml
version: "3.9"
services:
  nats:
    image: nats:latest   # 6 MB official image[4][14]
    command: -js -sd /data/jetstream -m 8222
    ports:
      - "4222:4222"
      - "8222:8222"
    volumes:
      - nats_data:/data
volumes:
  nats_data:
```

On first login:

```bash
docker compose up -d
```

Colima automatically exposes the mapped ports to macOS.

## 4. Creating additional leafs

1. Copy the repository:

```bash
cp -R cim-leaf-darwin cim-leaf-alpine     # example
cd cim-leaf-alpine && git init
```

2. Change only:
   * hostname output in `flake.nix`  
   * any leaf-specific Home-Manager packages or NATS credentials in `home.nix`.

3. Activate:

```bash
darwin-rebuild switch --flake .#alpine
```

## 5. Routine operations

| Task | Command |
|------|---------|
| Upgrade everything (macOS settings, pkgs, VM) | `nix flake update && darwin-rebuild switch --flake .#$(hostname)` |
| Start/stop the Colima VM | `colima start` / `colima stop` |
| Rebuild only user environment | `home-manager switch --flake .` |
| Check NATS health | `curl http://localhost:8222/varz` |

## 6. Why this stack

* **nix-darwin** brings NixOS-style declarative configs to macOS[4][5].  
* **Home-Manager** keeps dotfiles per-user and portable to Linux builders[6][7].  
* **Colima** gives a headless Linux VM with Docker API in < 150 MiB and is packaged in Nixpkgs, avoiding Docker Desktop licensing[8][9][10].  
* **Official `nats` image** is only 6 MiB and perfectly suited for a small JetStream node[11][12].  

All layers are reproducible: wipe `/nix`, reclone, run one command, and the Mac becomes a CIM leaf again.

### Footnotes

[1] NixCademy – installing Nix on macOS  
[6] Home-Manager manual – flake integration  
[11] NATS Docker tutorial  
[2] Official Nix download page – multi-user install  
[7] Davis Haupt – macOS with nix-darwin + Home-Manager  
[3] Fatih blog – reasons for Nix on macOS  
[4] nix-darwin GitHub – flake-first workflow  
[12] NATS docs – container ports  
[8] Colima README – features & install  
[9] Colima manpage – CLI flags  
[10] Qiita – Colima with Nix on Mac tips

[1] https://nixcademy.com/posts/nix-on-macos/
[2] https://nixos.org/download/
[3] https://blog.6nok.org/how-i-use-nix-on-macos/
[4] https://github.com/nix-darwin/nix-darwin
[5] https://www.youtube.com/watch?v=iU7B76NTr2I
[6] https://nix-community.github.io/home-manager/
[7] https://davi.sh/blog/2024/02/nix-home-manager/
[8] https://github.com/abiosoft/colima/blob/main/README.md?plain=1
[9] https://linuxcommandlibrary.com/man/colima
[10] https://qiita.com/kino-ma/items/8a9353f5b93b72c73dd4
[11] https://docs.nats.io/running-a-nats-service/nats_docker/nats-docker-tutorial
[12] https://docs.nats.io/running-a-nats-service/nats_docker
[13] https://github.com/heywoodlh/nix-darwin-flake
[14] https://www.nixhub.io/packages/nats-server
[15] https://discourse.nixos.org/t/nix-darwin-home-manager-and-flakes-how-to-set-environment-variables-for-the-main-user/34198
[16] https://github.com/nats-io/nats-docker
[17] https://www.nixhub.io/packages/nats-top
[18] https://www.reddit.com/r/NixOS/comments/17fzlk5/nix_nixdarwin_home_manager/
[19] https://bmcgee.ie/posts/2023/06/nats-building-a-nix-binary-cache/
[20] https://ianthehenry.com/posts/how-to-learn-nix/installing-nix-on-macos/
[21] https://gist.github.com/jmatsushita/5c50ef14b4b96cb24ae5268dab613050
[22] https://github.com/nats-io/nats.go/discussions/1130
[23] https://search.nixos.org/packages?show=nats-server&type=packages
[24] https://rickhenry.dev/blog/posts/2023-06-29-dev-without-docker/
[25] https://stackoverflow.com/questions/72557053/why-does-colima-failed-to-find-docker-daemon
[26] https://github.com/LnL7/nix-darwin/issues/1212
[27] https://stackoverflow.com/questions/75448509/how-to-manage-colima-docker-effectively
[28] https://www.reddit.com/r/NixOS/comments/1k48yqr/shared_home_manager_between_nixos_and_nixdarwin/
[29] https://dev.to/netoht/colima-in-macos-44g
[30] https://github.com/LnL7/nix-darwin/issues/1182
[31] https://github.com/abiosoft/colima/discussions/1117
[32] https://kodekloud.com/community/t/because-you-are-using-a-docker-driver-on-darwin-the-terminal-needs-to-be-open-to-run-it-on-mac-os/430680
[33] https://pkg.go.dev/github.com/abiosoft/colima
[34] https://dischord.org/2024/10/27/cloud-native-development-with-colima/
[35] https://github.com/doriancodes/colima-k8s-nix
[36] https://stackoverflow.com/questions/78187246/cant-start-complete-colima-docker-engine-as-x86-64-on-arm64
[37] https://dev.to/doriancodes/colima-k8s-nix-setup-mpn
[38] https://discuss.linuxcontainers.org/t/easy-way-to-try-incus-on-macos-with-colima/21153
[39] https://gist.github.com/yihuang/f197207bd290b63e639a9116db9e654a
[40] https://github.com/dhodvogner/colima-desktop
