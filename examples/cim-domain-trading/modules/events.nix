# Trading domain event definitions
{ config, lib, pkgs, ... }:

{
  # Event subject mappings for trading domain
  environment.variables = {
    # Order events
    NATS_EVENT_ORDER_CREATED = "cim.trading.events.order.created";
    NATS_EVENT_ORDER_FILLED = "cim.trading.events.order.filled";
    NATS_EVENT_ORDER_CANCELLED = "cim.trading.events.order.cancelled";
    NATS_EVENT_ORDER_REJECTED = "cim.trading.events.order.rejected";
    
    # Trade events
    NATS_EVENT_TRADE_EXECUTED = "cim.trading.events.trade.executed";
    NATS_EVENT_TRADE_SETTLED = "cim.trading.events.trade.settled";
    
    # Position events
    NATS_EVENT_POSITION_OPENED = "cim.trading.events.position.opened";
    NATS_EVENT_POSITION_UPDATED = "cim.trading.events.position.updated";
    NATS_EVENT_POSITION_CLOSED = "cim.trading.events.position.closed";
    
    # Market data events
    NATS_EVENT_PRICE_UPDATED = "cim.trading.events.market.price_updated";
    NATS_EVENT_QUOTE_RECEIVED = "cim.trading.events.market.quote_received";
  };
  
  # JetStream streams for event storage
  system.activationScripts.trading-streams = {
    text = ''
      # Wait for NATS to be ready
      while ! ${pkgs.natscli}/bin/nats account info &>/dev/null; do
        echo "Waiting for NATS..."
        sleep 2
      done
      
      # Create order events stream
      ${pkgs.natscli}/bin/nats stream add TRADING_ORDERS \
        --subjects "cim.trading.events.order.*" \
        --retention limits \
        --max-age 30d \
        --max-bytes 10G \
        --storage file \
        --replicas 1 \
        --no-deny-delete \
        --no-deny-purge \
        || true
      
      # Create trade events stream
      ${pkgs.natscli}/bin/nats stream add TRADING_TRADES \
        --subjects "cim.trading.events.trade.*" \
        --retention limits \
        --max-age 90d \
        --max-bytes 50G \
        --storage file \
        --replicas 1 \
        || true
      
      # Create position events stream
      ${pkgs.natscli}/bin/nats stream add TRADING_POSITIONS \
        --subjects "cim.trading.events.position.*" \
        --retention limits \
        --max-age 7d \
        --max-bytes 5G \
        --storage file \
        --replicas 1 \
        || true
    '';
  };
}