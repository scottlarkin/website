defmodule AgentBackend.SystemPromptTest do
  use ExUnit.Case, async: true

  alias AgentBackend.SystemPrompt

  test "loads from explicit path" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "prompt-test-#{System.unique_integer([:positive])}.md")
    File.write!(path, "  Hello from fixture prompt  \n")

    assert SystemPrompt.load(paths: [path]) == "Hello from fixture prompt"
  after
    :ok
  end

  test "falls back to SYSTEM_PROMPT env when file missing" do
    System.put_env("SYSTEM_PROMPT", "from-env-prompt")
    assert SystemPrompt.load(paths: ["/nonexistent/prompt.md"]) == "from-env-prompt"
  after
    System.delete_env("SYSTEM_PROMPT")
  end

  test "falls back to default when no file and no env" do
    System.delete_env("SYSTEM_PROMPT")
    out = SystemPrompt.load(paths: ["/nonexistent/prompt.md"])
    assert out =~ "Scott"
  end
end
