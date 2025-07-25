# CIM Network Topology Definition
# This file defines the complete CIM network topology
{ lib, ... }:

{
  # Global cluster configuration
  cluster = {
    name = "cim-global";
    description = "Global CIM cluster topology";
    version = "1.0.0";
  };

  # Geographic regions
  regions = {
    "us-east-1" = {
      name = "US East (Virginia)";
      timezone = "America/New_York";
      primary = true; # Primary region for global coordination
    };
    
    "us-west-2" = {
      name = "US West (Oregon)";
      timezone = "America/Los_Angeles";
    };
    
    "eu-central-1" = {
      name = "EU Central (Frankfurt)";
      timezone = "Europe/Berlin";
    };
    
    "ap-northeast-1" = {
      name = "Asia Pacific (Tokyo)";
      timezone = "Asia/Tokyo";
    };
  };

  # Hub nodes (NATS super-clusters)
  hubs = {
    "hub-us-east-1" = {
      region = "us-east-1";
      endpoints = [
        "nats://hub-us-east-1a.cim.internal:4222"
        "nats://hub-us-east-1b.cim.internal:4222"
        "nats://hub-us-east-1c.cim.internal:4222"
      ];
      
      # Gateway connections to other regions
      gateways = [
        {
          name = "us-west-2";
          urls = [ "nats://hub-us-west-2.cim.internal:7222" ];
        }
        {
          name = "eu-central-1";
          urls = [ "nats://hub-eu-central-1.cim.internal:7222" ];
        }
        {
          name = "ap-northeast-1";
          urls = [ "nats://hub-ap-northeast-1.cim.internal:7222" ];
        }
      ];
    };
    
    "hub-us-west-2" = {
      region = "us-west-2";
      endpoints = [
        "nats://hub-us-west-2.cim.internal:4222"
      ];
    };
    
    "hub-eu-central-1" = {
      region = "eu-central-1";
      endpoints = [
        "nats://hub-eu-central-1.cim.internal:4222"
      ];
    };
    
    "hub-ap-northeast-1" = {
      region = "ap-northeast-1";
      endpoints = [
        "nats://hub-ap-northeast-1.cim.internal:4222"
      ];
    };
  };

  # Domain definitions
  domains = {
    trading = {
      description = "Real-time trading and order management";
      primaryRegion = "us-east-1";
      
      # Subject namespace
      subjects = {
        events = "cim.trading.events.>";
        commands = "cim.trading.commands.>";
        queries = "cim.trading.queries.>";
      };
      
      # Required leaf nodes
      requiredLeafs = [ "prod" "staging" ];
      
      # Domain-specific configuration
      config = {
        maxOrderSize = "1000000"; # USD
        tickSize = "0.01";
        settlementDelay = "T+2";
      };
    };
    
    analytics = {
      description = "Data analytics and reporting";
      primaryRegion = "us-west-2";
      
      subjects = {
        events = "cim.analytics.events.>";
        commands = "cim.analytics.commands.>";
        queries = "cim.analytics.queries.>";
      };
      
      requiredLeafs = [ "prod" ];
      
      config = {
        retentionDays = 365;
        aggregationIntervals = [ "1m" "5m" "1h" "1d" ];
      };
    };
    
    risk = {
      description = "Risk management and compliance";
      primaryRegion = "eu-central-1";
      
      subjects = {
        events = "cim.risk.events.>";
        commands = "cim.risk.commands.>";
        queries = "cim.risk.queries.>";
      };
      
      requiredLeafs = [ "prod" ];
      
      config = {
        maxExposure = "10000000"; # USD
        marginRequirement = "0.20"; # 20%
      };
    };
  };

  # Leaf node assignments
  leafs = {
    # Production leafs
    "prod-trading-us-east-1" = {
      domain = "trading";
      environment = "prod";
      region = "us-east-1";
      hub = "hub-us-east-1";
      
      hosts = {
        primary = "10.1.1.10";
        secondaries = [ "10.1.1.11" "10.1.1.12" ];
      };
    };
    
    "prod-trading-ap-northeast-1" = {
      domain = "trading";
      environment = "prod";
      region = "ap-northeast-1";
      hub = "hub-ap-northeast-1";
      
      hosts = {
        primary = "10.4.1.10";
        secondaries = [ "10.4.1.11" ];
      };
    };
    
    "prod-analytics-us-west-2" = {
      domain = "analytics";
      environment = "prod";
      region = "us-west-2";
      hub = "hub-us-west-2";
      
      hosts = {
        primary = "10.2.1.10";
        secondaries = [];
      };
    };
    
    "prod-risk-eu-central-1" = {
      domain = "risk";
      environment = "prod";
      region = "eu-central-1";
      hub = "hub-eu-central-1";
      
      hosts = {
        primary = "10.3.1.10";
        secondaries = [ "10.3.1.11" ];
      };
    };
    
    # Staging leafs
    "staging-trading-us-east-1" = {
      domain = "trading";
      environment = "staging";
      region = "us-east-1";
      hub = "hub-us-east-1";
      
      hosts = {
        primary = "10.1.2.10";
        secondaries = [];
      };
    };
    
    # Development leafs
    "dev-trading-local" = {
      domain = "trading";
      environment = "dev";
      region = "us-east-1"; # Default for local dev
      hub = "hub-us-east-1";
      
      hosts = {
        primary = "localhost";
        secondaries = [];
      };
    };
  };

  # Network policies
  policies = {
    # Cross-domain event routing
    routing = {
      # Trading events can flow to analytics
      "trading->analytics" = {
        source = "cim.trading.events.>";
        destination = "cim.analytics.ingest.trading.>";
        filter = null; # No filtering
      };
      
      # Trading events flow to risk for monitoring
      "trading->risk" = {
        source = "cim.trading.events.order.>";
        destination = "cim.risk.monitor.orders.>";
        filter = "largeOrders"; # Only orders > $100k
      };
    };
    
    # Security policies
    security = {
      # Inter-region encryption
      interRegionTLS = true;
      
      # Require authentication for leaf connections
      requireAuth = true;
      
      # IP allowlists per region
      allowlists = {
        "us-east-1" = [ "10.1.0.0/16" ];
        "us-west-2" = [ "10.2.0.0/16" ];
        "eu-central-1" = [ "10.3.0.0/16" ];
        "ap-northeast-1" = [ "10.4.0.0/16" ];
      };
    };
    
    # Performance policies
    performance = {
      # Max message size
      maxPayload = "8MB";
      
      # Connection limits per leaf
      maxConnections = 1000;
      
      # Bandwidth limits (optional)
      bandwidthLimits = {
        interRegion = "100MB/s";
        leafToHub = "50MB/s";
      };
    };
  };

  # Monitoring and observability
  observability = {
    # Central monitoring endpoints
    prometheus = {
      global = "https://prometheus.cim.global";
      federation = true;
    };
    
    grafana = {
      global = "https://grafana.cim.global";
      
      # Pre-configured dashboards
      dashboards = [
        "cluster-overview"
        "leaf-status"
        "domain-metrics"
        "network-topology"
      ];
    };
    
    # Distributed tracing
    tracing = {
      enable = true;
      jaeger = "https://jaeger.cim.global";
      samplingRate = 0.01; # 1%
    };
  };

  # Disaster recovery
  disasterRecovery = {
    # Backup regions for each primary
    backupRegions = {
      "us-east-1" = "us-west-2";
      "us-west-2" = "us-east-1";
      "eu-central-1" = "us-east-1";
      "ap-northeast-1" = "us-west-2";
    };
    
    # Automatic failover
    autoFailover = {
      enable = true;
      healthCheckInterval = "30s";
      failoverThreshold = 3; # Missed health checks
    };
  };
}