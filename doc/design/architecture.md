# CIM Leaf Darwin Architecture

## Overview

This is a Darwin (macOS) implementation of a CIM leaf node using nix-darwin for reproducible system configuration.

## Key Components

### 1. System Layer (nix-darwin)
- Declarative macOS configuration
- Package management via Nix
- Service management via launchd

### 2. NATS Messaging
- JetStream enabled for persistent messaging
- Running as launchd daemon
- Ports: 4222 (client), 8222 (monitoring)

### 3. Development Environment
- Rust toolchain for CIM modules
- direnv for automatic environment loading
- Helix as primary editor

## Design Decisions

### Why No Docker/Containers
- Native launchd services are more efficient on macOS
- Avoids VM overhead of Docker Desktop/Colima
- Simpler architecture with fewer moving parts
- Better integration with macOS security features

### Module Structure (Planned)
Following DDD and CQRS patterns as specified in `.claude/`:
- `cim_core` - Core domain types
- `cim_events` - Event infrastructure
- `cim_commands` - Command processing
- `cim_projections` - Read model builders
- `cim_nats` - NATS integration
- `cim_leaf` - Leaf node specifics

## Next Implementation Steps
1. Create Rust workspace structure
2. Implement core domain types
3. Set up NATS event streaming
4. Build first command handler