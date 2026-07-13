import Config

host = System.get_env("PHX_HOST")

if host do
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

  config :agent_backend, AgentBackendWeb.Endpoint,
    url: [
      host: host || "scott.larkin.cc",
      port: 443,
      scheme: "https"
    ],
    secret_key_base: secret_key_base,
    live_view: [signing_salt: live_view_salt],
    server: true
end
