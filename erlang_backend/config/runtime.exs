import Config

# Override listen port for local dev/testing without touching prod (default 3000).
# Example: PORT=3001 mix phx.server  — or use scripts/dev-server.sh
if env_port = System.get_env("PORT") do
  port = String.to_integer(env_port)

  config :agent_backend, AgentBackendWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    url: [host: System.get_env("PHX_URL_HOST") || "localhost", port: port]
end

if config_env() == :dev do
  secret_key_base = System.get_env("SECRET_KEY_BASE")

  if is_binary(secret_key_base) and byte_size(secret_key_base) >= 64 do
    config :agent_backend, AgentBackendWeb.Endpoint, secret_key_base: secret_key_base
  end
end

# Prod public URL only — don't override dev/test instances on alternate ports.
host = System.get_env("PHX_HOST")

if host && config_env() == :prod do
  config :agent_backend, AgentBackendWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"]
end

if config_env() == :prod do
  secret_key_base = System.get_env("SECRET_KEY_BASE")
  live_view_salt = System.get_env("LIVE_VIEW_SALT")

  if is_nil(secret_key_base) or secret_key_base == "" do
    raise """
    SECRET_KEY_BASE is missing.

    Generate one with: mix phx.gen.secret
    Then set it in .env or your deployment environment.
    """
  end

  if is_nil(live_view_salt) or live_view_salt == "" do
    raise """
    LIVE_VIEW_SALT is missing.

    Generate one with: mix phx.gen.secret
    Then set it in .env or your deployment environment.
    """
  end

  public_host = host || "scott.larkin.cc"

  config :agent_backend, AgentBackendWeb.Endpoint,
    url: [
      host: public_host,
      port: 443,
      scheme: "https"
    ],
    secret_key_base: secret_key_base,
    live_view: [signing_salt: live_view_salt],
    server: true,
    # Restrict LiveView WebSocket origins in production
    check_origin: [
      "//#{public_host}",
      "https://#{public_host}",
      "http://localhost:3000",
      "http://127.0.0.1:3000"
    ]
end

