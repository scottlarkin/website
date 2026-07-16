defmodule AgentBackend.StreamSyncTest do
  use ExUnit.Case, async: false

  alias AgentBackend.AgentRuns
  alias AgentBackend.TestHelpers

  setup do
    TestHelpers.setup_fakes()
    chat = TestHelpers.unique_chat_id()
    run = "run-sync-1"

    messages = [
      %{role: "user", content: "hi", timestamp: "t1"},
      %{role: "assistant", content: "", timestamp: "t2"}
    ]

    on_exit(fn -> TestHelpers.finish_run(chat) end)

    assert :ok = AgentRuns.try_start(chat, run, messages)
    {:ok, chat: chat, run: run}
  end

  test "absolute snapshots keep two subscribers in lockstep", %{chat: chat, run: run} do
    topic = "chat:#{chat}"
    Phoenix.PubSub.subscribe(AgentBackend.PubSub, topic)
    Phoenix.PubSub.subscribe(AgentBackend.PubSub, topic)

    assert {:ok, snap1} = AgentRuns.append_token(chat, run, "Hel")
    broadcast(chat, run, snap1)

    assert_receive {:agent_event, ^run, {:stream_state, s1a}}, 200
    assert_receive {:agent_event, ^run, {:stream_state, s1b}}, 200
    assert List.last(s1a.messages).content == "Hel"
    assert List.last(s1b.messages).content == "Hel"

    assert {:ok, snap2} = AgentRuns.append_token(chat, run, "lo")
    broadcast(chat, run, snap2)

    assert_receive {:agent_event, ^run, {:stream_state, s2a}}, 200
    assert_receive {:agent_event, ^run, {:stream_state, s2b}}, 200
    assert List.last(s2a.messages).content == "Hello"
    assert List.last(s2b.messages).content == "Hello"
    assert s2a.messages == s2b.messages
  end

  test "late join via live_state sees current content", %{chat: chat, run: run} do
    assert {:ok, _} = AgentRuns.append_token(chat, run, "partial")
    live = AgentRuns.live_state(chat)
    assert live.run_id == run
    assert List.last(live.messages).content == "partial"
  end

  defp broadcast(chat_id, run_id, snapshot) do
    Phoenix.PubSub.broadcast(
      AgentBackend.PubSub,
      "chat:#{chat_id}",
      {:agent_event, run_id, {:stream_state, snapshot}}
    )
  end
end
