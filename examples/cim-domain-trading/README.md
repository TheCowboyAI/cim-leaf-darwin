# CIM Domain - Trading

Example domain repository structure for a trading domain.

## Structure

```
cim-domain-trading/
├── modules/
│   ├── events.nix       # Trading event definitions
│   ├── commands.nix     # Trading command handlers
│   ├── projections.nix  # Trading read models
│   └── rules.nix        # Business rules and validations
├── leaf-configs/
│   ├── prod.nix         # Production-specific overrides
│   └── dev.nix          # Development settings
├── schemas/
│   ├── order.json       # Order event schema
│   └── trade.json       # Trade event schema
└── tests/
    └── domain_tests.rs  # Domain logic tests
```

## Events

The trading domain publishes these events:

- `cim.trading.events.order.created`
- `cim.trading.events.order.filled`
- `cim.trading.events.order.cancelled`
- `cim.trading.events.trade.executed`
- `cim.trading.events.position.updated`

## Commands

The trading domain accepts these commands:

- `cim.trading.commands.order.create`
- `cim.trading.commands.order.cancel`
- `cim.trading.commands.position.close`

## Integration

Leaf nodes pull this domain by configuring their `leaf.config.json`:

```json
{
  "cim_domain": {
    "repository": "https://github.com/YourOrg/cim-domain-trading.git",
    "branch": "main"
  }
}
```