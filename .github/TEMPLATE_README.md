# CIM Leaf Darwin - Template Repository

This is a **template repository** for creating CIM leaf nodes on Darwin (macOS) systems.

## How to Use This Template

1. **Click "Use this template"** button above
2. Name your new repository following the pattern: `cim-leaf-[YOUR_LEAF_NAME]`
3. Clone your new repository and run `./scripts/setup_leaf.sh`

## What This Template Provides

- **Remote Deployment System**: Deploy nix-darwin configurations to remote Macs
- **Hardware Inventory Extraction**: Gather system information before deployment  
- **Domain Integration**: Connect to your CIM domain modules
- **NATS Clustering**: Automatic NATS configuration with upstream connections
- **Reproducible Builds**: Nix flakes ensure consistent deployments

## Template Structure

```
├── scripts/
│   ├── setup_leaf.sh         # Run this first!
│   ├── extract_inventory.sh  # Hardware discovery
│   ├── generate_config.sh    # Config generation
│   └── deploy_host.sh        # Remote deployment
├── modules/                  # Nix modules
├── .claude/                  # Development guidelines
└── leaf.config.json.template # Configuration template
```

## After Using This Template

Your first steps:
1. Run `./scripts/setup_leaf.sh` to configure your leaf
2. Commit and push your configuration
3. Start deploying to your Mac infrastructure

## Documentation

See the main README.md after running setup for detailed deployment instructions.

## Contributing

To improve this template, submit PRs to the original repository:
https://github.com/TheCowboyAI/cim-leaf-darwin