import Config

config :agent_backend, AgentBackendWeb.Endpoint,
  http: [port: 3000, ip: {0, 0, 0, 0}],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [],
  secret_key_base: "dev_only_not_for_production_use_mix_phx_gen_secret_in_env000",
  live_view: [signing_salt: "dev-live-view-salt"]
