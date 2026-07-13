import Config

config :agent_backend, AgentBackendWeb.Endpoint,
  http: [port: 4000],
  url: [host: "localhost", port: 4000],
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  root: ".",
  secret_key_base: System.get_env("SECRET_KEY_BASE"),
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SALT")]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
