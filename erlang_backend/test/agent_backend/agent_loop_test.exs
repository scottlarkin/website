defmodule AgentBackend.AgentLoopTest do
  use ExUnit.Case, async: false

  alias AgentBackend.AgentLoop
  alias AgentBackend.LLM.Fake, as: LLM
  alias AgentBackend.TestHelpers

  @history [%{role: "user", content: "hi"}]
  @sys "You are Scott. Worked at Ravio."

  setup do
    TestHelpers.setup_fakes()
    # Strict retries for tests
    System.put_env("AGENT_MAX_VALIDATION_RETRIES", "2")
    System.put_env("AGENT_MAX_ITERS", "5")
    :ok
  end

  test "happy path: stream + validator pass" do
    LLM.push_stream({:ok, "Hello there"})
    LLM.push_complete(~s({"passed": true}))

    {pid, cb} = TestHelpers.recorder()
    assert "Hello there" == AgentLoop.run(@history, @sys, cb)

    events = TestHelpers.events(pid)
    assert {:status, :generating} in events
    assert {:token, "Hello there"} in events
    assert {:done, %{validated: true}} in events
    refute Enum.any?(events, &match?({:error, _}, &1))
  end

  test "validation fail then revise then pass" do
    LLM.push_stream({:ok, "bad draft"})
    LLM.push_complete(~s({"passed": false, "issues": ["invented metrics"]}))
    LLM.push_stream({:ok, "good draft"})
    LLM.push_complete(~s({"passed": true}))

    {pid, cb} = TestHelpers.recorder()
    assert "good draft" == AgentLoop.run(@history, @sys, cb)

    events = TestHelpers.events(pid)
    assert :hold_draft in events
    assert {:status, :revising} in events
    assert {:token, "good draft"} in events
    assert {:done, %{validated: true}} in events
  end

  test "empty stream and empty complete yields on_error" do
    LLM.push_stream({:ok, ""})
    LLM.push_complete({:error, "still empty"})

    {pid, cb} = TestHelpers.recorder()
    assert nil == AgentLoop.run(@history, @sys, cb)

    events = TestHelpers.events(pid)
    assert :reset in events
    assert Enum.any?(events, &match?({:error, _}, &1))
  end

  test "stream error falls back to complete with on_reset first" do
    LLM.push_stream({:error, "sse failed"})
    LLM.push_complete({:ok, "recovered answer"})
    LLM.push_complete(~s({"passed": true}))

    {pid, cb} = TestHelpers.recorder()
    assert "recovered answer" == AgentLoop.run(@history, @sys, cb)

    events = TestHelpers.events(pid)
    reset_idx = Enum.find_index(events, &(&1 == :reset))
    token_idx = Enum.find_index(events, &match?({:token, "recovered answer"}, &1))
    assert reset_idx < token_idx
  end

  test "unwraps draft JSON and resets display" do
    wrapped = ~s({"draft": "unwrapped text"})
    LLM.push_stream({:ok, wrapped})
    LLM.push_complete(~s({"passed": true}))

    {pid, cb} = TestHelpers.recorder()
    assert "unwrapped text" == AgentLoop.run(@history, @sys, cb)

    events = TestHelpers.events(pid)
    assert :reset in events
    assert {:token, "unwrapped text"} in events
  end

  test "unparseable validator defaults to pass" do
    LLM.push_stream({:ok, "draft"})
    LLM.push_complete("not json at all")

    {pid, cb} = TestHelpers.recorder()
    assert "draft" == AgentLoop.run(@history, @sys, cb)
    assert {:done, %{validated: true}} in TestHelpers.events(pid)
  end

  test "exhausted validation retries accepts draft" do
    System.put_env("AGENT_MAX_VALIDATION_RETRIES", "0")

    LLM.push_stream({:ok, "imperfect"})
    LLM.push_complete(~s({"passed": false, "issues": ["x"]}))

    {pid, cb} = TestHelpers.recorder()
    assert "imperfect" == AgentLoop.run(@history, @sys, cb)
    assert {:done, %{validated: false}} in TestHelpers.events(pid)
  after
    System.put_env("AGENT_MAX_VALIDATION_RETRIES", "2")
  end

  test "stream hard error with no complete recovery" do
    LLM.push_stream({:error, "down"})
    LLM.push_complete({:error, "also down"})

    {pid, cb} = TestHelpers.recorder()
    assert nil == AgentLoop.run(@history, @sys, cb)
    assert Enum.any?(TestHelpers.events(pid), &match?({:error, _}, &1))
  end
end
