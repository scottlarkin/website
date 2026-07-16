defmodule AgentBackend.Tools.OutputValidatorTest do
  use ExUnit.Case, async: true

  alias AgentBackend.Tools.OutputValidator

  test "normalize_result defaults unparseable content to pass" do
    assert Jason.decode!(OutputValidator.normalize_result("lol not json")) == %{"passed" => true}
  end

  test "normalize_result defaults missing passed key to pass" do
    assert Jason.decode!(OutputValidator.normalize_result(~s({"ok": true}))) == %{"passed" => true}
  end

  test "normalize_result preserves explicit fail" do
    raw = ~s({"passed": false, "issues": ["invented employer"]})
    assert %{"passed" => false, "issues" => ["invented employer"]} = Jason.decode!(OutputValidator.normalize_result(raw))
  end

  test "normalize_result preserves explicit pass" do
    assert Jason.decode!(OutputValidator.normalize_result(~s({"passed": true}))) == %{"passed" => true}
  end

  test "execute uses configured LLM fake without network" do
    AgentBackend.LLM.Fake.setup()
    AgentBackend.LLM.Fake.push_complete(~s({"passed": false, "issues": ["invented metrics"]}))

    out =
      OutputValidator.execute(
        %{"draft" => "I made up $50M ARR"},
        %{system_prompt: "Worked at Ravio.", user_question: "tell me about work"}
      )

    assert %{"passed" => false, "issues" => ["invented metrics"]} = Jason.decode!(out)
  end

  test "execute API error defaults to pass" do
    AgentBackend.LLM.Fake.setup()
    AgentBackend.LLM.Fake.push_complete({:error, "network down"})

    out = OutputValidator.execute(%{"draft" => "hi"}, %{system_prompt: "x", user_question: "y"})
    assert Jason.decode!(out) == %{"passed" => true}
  end
end

