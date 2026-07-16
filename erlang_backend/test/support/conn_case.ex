defmodule AgentBackendWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      @endpoint AgentBackendWeb.Endpoint
    end
  end

  setup _tags do
    AgentBackend.TestHelpers.setup_fakes()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
