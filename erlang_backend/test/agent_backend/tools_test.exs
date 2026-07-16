defmodule AgentBackend.ToolsTest do
  use ExUnit.Case, async: false

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

  test "run_tool rescues exploding tools" do
    prev = Application.get_env(:agent_backend, :tools)

    try do
      Application.put_env(:agent_backend, :tools, [
        AgentBackend.Tools.OutputValidator,
        AgentBackend.Tools.Exploding
      ])

      body = Tools.run_tool("exploding_tool", %{}, %{})
      assert %{"passed" => true, "error" => "boom"} = Jason.decode!(body)
    after
      if prev do
        Application.put_env(:agent_backend, :tools, prev)
      else
        Application.delete_env(:agent_backend, :tools)
      end
    end
  end
end


