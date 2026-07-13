import Config

config :agent_backend,
  ecto_repos: []

config :agent_backend, AgentBackendWeb.Endpoint,
  http: [port: 3000, ip: {0, 0, 0, 0}],
  url: [host: "localhost", port: 3000],
  server: true,
  root: ".",
  check_origin: false

# Static asset configuration
config :esbuild,
  version: "0.24.0",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --external:phoenix --external:phoenix_live_view --external:topbar),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../assets/node_modules", __DIR__)}
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"