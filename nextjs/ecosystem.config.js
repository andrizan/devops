module.exports = {
  apps: [
    {
      name: "cms",
      cwd: "/var/www/cms",
      script: "./.next/standalone/server.js",
      instances: 2,
      exec_mode: "cluster",
      autorestart: true,
      watch: false,
      max_memory_restart: "512M",

      // Environment variables
      env_production: {
        NODE_ENV: "production",
        PORT: 3000,
        HOSTNAME: "0.0.0.0",
      },

      // Logging
      error_file: "/var/www/cms/logs/web-error.log",
      out_file: "/var/www/cms/logs/web-out.log",
      log_date_format: "YYYY-MM-DD HH:mm:ss Z",
      merge_logs: true,

      // Process management
      min_uptime: "10s",
      max_restarts: 10,
      restart_delay: 4000,

      // Advanced features
      kill_timeout: 5000,
      listen_timeout: 10000,

      // Next.js specific
      env: {
        NEXT_TELEMETRY_DISABLED: "1",
      },

      // Node.js memory optimization
      node_args: "--max-old-space-size=512", // Limit heap memory ke 512MB
    },
  ],
};
