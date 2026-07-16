defmodule AgentBackend.ToolsTest do
  use ExUnit.Case, async: true

  alias AgentBackend.Tools

  test "unknown tool returns JSON error without raising" do
    body = Tools.run_tool("nope", %{}, %{})
    assert %{"error" => err} = Jason.decode!(body)
    assert err =~ "unknown tool"
  end

  test "execute_all wraps tool results" do
    [result] =
      Tools.execute_all(
        [%{id: "1", name: "missing", arguments: %{}}],
        %{}
      )

    assert result.role == "tool"
    assert result.tool_call_id == "1"
    assert Jason.decode!(result.content)["error"]
  end
end
