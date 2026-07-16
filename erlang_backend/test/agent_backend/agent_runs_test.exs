defmodule AgentBackend.AgentRunsTest do
  use ExUnit.Case, async: false

  alias AgentBackend.AgentRuns

  @msgs [
    %{role: "user", content: "hi", timestamp: "t1"},
    %{role: "assistant", content: "", timestamp: "t2"}
  ]

  setup do
    for id <- ["runtest01", "runtest02", "runtest03"] do
      case AgentRuns.current_run(id) do
        nil -> :ok
        rid -> AgentRuns.finish(id, rid)
      end
    end

    :ok
  end

  test "try_start succeeds when free and busy when occupied" do
    chat = "runtest01"
    assert :ok = AgentRuns.try_start(chat, "r1", @msgs)
    assert AgentRuns.active?(chat)
    assert AgentRuns.current_run(chat) == "r1"
    assert {:error, :busy} = AgentRuns.try_start(chat, "r2", @msgs)
    assert :ok = AgentRuns.finish(chat, "r1")
    refute AgentRuns.active?(chat)
    assert :ok = AgentRuns.try_start(chat, "r3", @msgs)
    assert :ok = AgentRuns.finish(chat, "r3")
  end

  test "finish with wrong run_id does not clear active run" do
    chat = "runtest02"
    assert :ok = AgentRuns.try_start(chat, "keep", @msgs)
    assert :ok = AgentRuns.finish(chat, "other")
    assert AgentRuns.current_run(chat) == "keep"
    assert :ok = AgentRuns.finish(chat, "keep")
    refute AgentRuns.active?(chat)
  end

  test "append_token builds shared absolute content for multi-tab sync" do
    chat = "runtest03"
    assert :ok = AgentRuns.try_start(chat, "r1", @msgs)

    assert {:ok, snap1} = AgentRuns.append_token(chat, "r1", "Hel")
    assert {:ok, snap2} = AgentRuns.append_token(chat, "r1", "lo")

    assert List.last(snap1.messages).content == "Hel"
    assert List.last(snap2.messages).content == "Hello"
    assert snap2.is_loading == true

    live = AgentRuns.live_state(chat)
    assert List.last(live.messages).content == "Hello"

    assert :ok = AgentRuns.finish(chat, "r1")
    assert AgentRuns.live_state(chat) == nil
  end

  test "reset_assistant clears content without losing user turn" do
    chat = "runtest03"
    assert :ok = AgentRuns.try_start(chat, "r1", @msgs)
    assert {:ok, _} = AgentRuns.append_token(chat, "r1", "draft")
    assert {:ok, snap} = AgentRuns.reset_assistant(chat, "r1")
    assert length(snap.messages) == 2
    assert List.last(snap.messages).content == ""
    assert :ok = AgentRuns.finish(chat, "r1")
  end

  test "full hub lifecycle hold_draft status error" do
    chat = "runtest01"
    assert :ok = AgentRuns.try_start(chat, "life", @msgs)
    assert {:ok, _} = AgentRuns.append_token(chat, "life", "draft A")
    assert {:ok, held} = AgentRuns.hold_draft(chat, "life")
    assert held.held_draft == "draft A"
    assert held.agent_status == :revising

    assert {:ok, reset} = AgentRuns.reset_assistant(chat, "life")
    assert List.last(reset.messages).content == ""

    assert {:ok, st} = AgentRuns.set_status(chat, "life", :generating)
    assert st.agent_status == :generating

    assert {:ok, err} = AgentRuns.set_error(chat, "life", "Something went wrong")
    assert List.last(err.messages).error == true
    assert List.last(err.messages).content =~ "wrong"

    assert :ignore = AgentRuns.append_token(chat, "wrong-run", "x")
    assert :ok = AgentRuns.finish(chat, "life")
    assert AgentRuns.live_state(chat) == nil
  end

  test "serialized concurrent appends" do
    chat = "runtest02"
    assert :ok = AgentRuns.try_start(chat, "c", @msgs)

    1..20
    |> Enum.map(fn i -> Task.async(fn -> AgentRuns.append_token(chat, "c", "#{i}") end) end)
    |> Enum.each(&Task.await/1)

    content = List.last(AgentRuns.live_state(chat).messages).content
    # All digits 1-20 appear (order may interleave by task scheduling but GenServer serializes)
    for i <- 1..20 do
      assert content =~ "#{i}"
    end

    assert :ok = AgentRuns.finish(chat, "c")
  end
end
