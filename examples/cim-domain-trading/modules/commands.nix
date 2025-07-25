# Trading domain command definitions
{ config, lib, pkgs, ... }:

{
  # Command subject mappings for trading domain
  environment.variables = {
    # Order commands
    NATS_CMD_ORDER_CREATE = "cim.trading.commands.order.create";
    NATS_CMD_ORDER_CANCEL = "cim.trading.commands.order.cancel";
    NATS_CMD_ORDER_MODIFY = "cim.trading.commands.order.modify";
    
    # Position commands
    NATS_CMD_POSITION_CLOSE = "cim.trading.commands.position.close";
    NATS_CMD_POSITION_ADJUST = "cim.trading.commands.position.adjust";
    
    # Risk management commands
    NATS_CMD_RISK_CHECK = "cim.trading.commands.risk.check";
    NATS_CMD_MARGIN_CALCULATE = "cim.trading.commands.margin.calculate";
  };
  
  # Command validation rules
  system.activationScripts.trading-command-consumers = {
    text = ''
      # Create durable consumers for command processing
      
      # Order command processor
      ${pkgs.natscli}/bin/nats consumer add TRADING_ORDERS ORDER_COMMANDS \
        --filter "cim.trading.commands.order.*" \
        --ack explicit \
        --max-deliver 3 \
        --max-ack-pending 100 \
        --deliver all \
        --replay instant \
        || true
    '';
  };
}