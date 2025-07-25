{ config, lib, pkgs, leafConfig, ... }:

let
  promPort = 9090;
  grafanaPort = 3000;
  natsExporterPort = 7777;
in
{
  # Prometheus for metrics collection
  launchd.daemons.prometheus = {
    enable = true;
    config = {
      Label = "org.prometheus.prometheus";
      ProgramArguments = [
        "${pkgs.prometheus}/bin/prometheus"
        "--config.file=/etc/prometheus/prometheus.yml"
        "--storage.tsdb.path=/var/lib/prometheus"
        "--web.listen-address=:${toString promPort}"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardErrorPath = "/var/log/prometheus/error.log";
      StandardOutPath = "/var/log/prometheus/output.log";
    };
  };

  # NATS Prometheus exporter
  launchd.daemons.nats-exporter = {
    enable = true;
    config = {
      Label = "org.prometheus.nats-exporter";
      ProgramArguments = [
        "${pkgs.prometheus-nats-exporter}/bin/nats_exporter"
        "-varz" "http://localhost:8222"
        "-port" "${toString natsExporterPort}"
      ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  # Node exporter for system metrics
  launchd.daemons.node-exporter = {
    enable = true;
    config = {
      Label = "org.prometheus.node-exporter";
      ProgramArguments = [
        "${pkgs.prometheus-node-exporter}/bin/node_exporter"
        "--web.listen-address=:9100"
      ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  # Grafana for visualization
  launchd.daemons.grafana = lib.mkIf (leafConfig.leaf.environment != "prod") {
    enable = true;
    config = {
      Label = "com.grafana.grafana";
      ProgramArguments = [
        "${pkgs.grafana}/bin/grafana-server"
        "--homepath=${pkgs.grafana}/share/grafana"
        "--config=/etc/grafana/grafana.ini"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "/var/lib/grafana";
      EnvironmentVariables = {
        GF_PATHS_DATA = "/var/lib/grafana";
        GF_PATHS_LOGS = "/var/log/grafana";
        GF_PATHS_PLUGINS = "/var/lib/grafana/plugins";
        GF_PATHS_PROVISIONING = "/etc/grafana/provisioning";
      };
    };
  };

  # Create monitoring directories
  system.activationScripts.monitoring = {
    text = ''
      echo "Setting up monitoring directories..."
      mkdir -p /var/lib/prometheus
      mkdir -p /var/log/prometheus
      mkdir -p /var/lib/grafana
      mkdir -p /var/log/grafana
      mkdir -p /etc/prometheus
      mkdir -p /etc/grafana/provisioning/{dashboards,datasources}
      
      # Prometheus configuration
      cat > /etc/prometheus/prometheus.yml << 'EOF'
      global:
        scrape_interval: 15s
        evaluation_interval: 15s
        external_labels:
          leaf: '${leafConfig.leaf.name}'
          domain: '${leafConfig.leaf.domain}'
          region: '${leafConfig.leaf.region}'
          environment: '${leafConfig.leaf.environment}'

      scrape_configs:
        - job_name: 'node'
          static_configs:
            - targets: ['localhost:9100']
        
        - job_name: 'nats'
          static_configs:
            - targets: ['localhost:${toString natsExporterPort}']
        
        - job_name: 'prometheus'
          static_configs:
            - targets: ['localhost:${toString promPort}']
      EOF

      # Grafana configuration
      cat > /etc/grafana/grafana.ini << 'EOF'
      [server]
      http_port = ${toString grafanaPort}
      
      [security]
      admin_user = admin
      admin_password = ${leafConfig.leaf.name}-admin
      
      [auth.anonymous]
      enabled = true
      org_role = Viewer
      EOF

      # Grafana datasource
      cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'EOF'
      apiVersion: 1
      datasources:
        - name: Prometheus
          type: prometheus
          access: proxy
          url: http://localhost:${toString promPort}
          isDefault: true
      EOF
    '';
  };

  # Add monitoring tools to system packages
  environment.systemPackages = with pkgs; [
    prometheus
    prometheus-node-exporter
    prometheus-nats-exporter
    grafana
  ];

  # Environment variables for monitoring
  environment.variables = {
    PROMETHEUS_URL = "http://localhost:${toString promPort}";
    GRAFANA_URL = "http://localhost:${toString grafanaPort}";
  };
}