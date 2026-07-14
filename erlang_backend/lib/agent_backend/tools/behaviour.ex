defmodule AgentBackend.Tools.Behaviour do
  @callback name() :: String.t()
  @callback schema() :: map()
  @callback status_label() :: String.t()
  @callback execute(arguments :: map(), ctx :: map()) :: String.t()
end