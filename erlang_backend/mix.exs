defmodule AgentBackend.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_backend,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "assets.build": [
        "cmd --cd assets npm ci",
        "esbuild default",
        "cmd --cd assets npm run build"
      ],
      "assets.deploy": ["assets.build", "phx.digest"]
    ]
  end

  def application do
    [
      mod: {AgentBackend.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_pubsub, "~> 2.2"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_view, "~> 2.0"},
      {:gettext, "~> 0.20"},
      {:plug_cowboy, "~> 2.9"},
      {:jason, "~> 1.4"},
      {:cors_plug, "~> 3.0"},
      {:telemetry, "~> 1.4"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:bandit, "~> 1.12"},
      {:esbuild, "~> 0.8", runtime: false},
      {:req, "~> 0.5"},
      {:earmark, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end

