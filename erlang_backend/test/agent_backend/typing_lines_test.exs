defmodule AgentBackendWeb.TypingLinesTest do
  use ExUnit.Case, async: true

  alias AgentBackendWeb.TypingLines

  test "random_line avoids repeating other when possible" do
    line = TypingLines.random_line()
    other = TypingLines.random_line(line)
    # With many lines, almost always different; allow rare collision only if single line
    if length(TypingLines.lines()) > 1 do
      assert other != line
    end
  end

  test "lines are non-empty and without ellipsis" do
    for line <- TypingLines.lines() do
      assert is_binary(line)
      assert line != ""
      refute String.ends_with?(line, "…")
      refute String.ends_with?(line, "...")
    end
  end
end
