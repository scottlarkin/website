import Config

config :agent_backend, AgentBackendWeb.Endpoint,
  http: [port: 4002, ip: {127, 0, 0, 1}],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test-live-view-salt"],
  check_origin: false

# Isolated session files for tests (created per test module via Application.put_env when needed)
config :agent_backend,
  chat_sessions_dir: Path.expand("../tmp/test_chat_sessions", __DIR__)

config :logger, level: :warning
