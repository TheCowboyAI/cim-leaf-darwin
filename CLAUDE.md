# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a CIM (Composable Information Machine) leaf node for Darwin (macOS). The project uses Nix flakes for reproducible builds and nix-darwin for system configuration. Currently in initial setup phase with comprehensive architectural documentation in `.claude/`.

## Development Commands

### System Setup and Rebuilds
```bash
# Apply system configuration changes
darwin-rebuild switch --flake .#"$(scutil --get LocalHostName)"

# Update dependencies and rebuild
nix flake update && darwin-rebuild switch --flake .#$(hostname)

# Update user environment (when home.nix exists)
home-manager switch --flake .
```

### NATS/Docker Management
```bash
# Start NATS with JetStream (when docker-compose.yaml exists)
docker compose up -d

# View NATS logs
docker compose logs -f
```

## Architecture and Principles

### Core Architecture
- **Event-Driven**: Built on immutable events with NATS messaging
- **Domain-Driven Design**: Strict layer boundaries (Presentation → Application → Domain → Infrastructure)
- **CQRS with Event Sourcing**: Commands produce events, projections build read models
- **Graph-Based Workflows**: Processes represented as directed acyclic graphs
- **Bevy ECS Integration**: For visualization and real-time monitoring

### Development Principles
1. **Lowercase filenames only** - Use snake_case for all files
2. **Test-Driven Development** - Write tests first
3. **Incremental Building** - Build functionality in small, testable increments
4. **Module Independence** - Each module has single responsibility with clear boundaries

### Module Structure
Key modules as defined in `.claude/cim-modules.mdc`:
- `cim_core`: Core domain types and traits
- `cim_events`: Event infrastructure and persistence
- `cim_commands`: Command processing and validation
- `cim_projections`: Read model builders
- `cim_workflow`: Process orchestration
- `cim_nats`: NATS messaging integration
- `cim_bevy`: Visualization layer

### Anti-Patterns to Avoid
- Direct infrastructure access from domain layer
- Synchronous inter-module communication
- Mutable shared state
- Circular dependencies between modules

## Environment Setup

The project requires:
1. Nix with experimental features enabled
2. nix-darwin for macOS configuration
3. Colima for container runtime (alternative to Docker Desktop)
4. direnv for environment management

## Configuration Files

When created, the following files will be important:
- `flake.nix`: Main Nix flake configuration
- `darwin.nix`: macOS system configuration
- `home.nix`: User environment configuration
- `docker-compose.yaml`: NATS container setup
- `.envrc`: direnv configuration for automatic environment loading

## Testing Approach

Testing strategy follows the architecture layers:
- Unit tests for domain logic
- Integration tests for infrastructure adapters
- End-to-end tests for workflows
- Property-based tests for event sourcing invariants

Note: Specific test commands will depend on the language/framework chosen for implementation.