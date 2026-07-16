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
    assert :already_done = AgentRuns.finish(chat, "other")
    assert AgentRuns.current_run(chat) == "keep"
    assert :ok = AgentRuns.finish(chat, "keep")
    refute AgentRuns.active?(chat)
    assert :already_done = AgentRuns.finish(chat, "keep")
  end

  test "cancel keeps partial content and frees single-flight" do
    chat = "runtest01"
    assert :ok = AgentRuns.try_start(chat, "c1", @msgs)
    assert {:ok, _} = AgentRuns.append_token(chat, "c1", "Hello partial")

    assert {:ok, settled} = AgentRuns.cancel(chat, "c1")
    assert length(settled) == 2
    assert List.last(settled).content == "Hello partial"
    refute Map.get(List.last(settled), :error)
    refute AgentRuns.active?(chat)
    assert :ignore = AgentRuns.cancel(chat, "c1")
    assert :ok = AgentRuns.try_start(chat, "c2", @msgs)
    assert :ok = AgentRuns.finish(chat, "c2")
  end

  test "cancel drops empty assistant placeholder" do
    chat = "runtest02"
    assert :ok = AgentRuns.try_start(chat, "empty", @msgs)
    assert {:ok, settled} = AgentRuns.cancel(chat, "empty")
    assert length(settled) == 1
    assert hd(settled).role == "user"
    refute AgentRuns.active?(chat)
  end

  test "cancel kills registered runner and finish is already_done" do
    chat = "runtest03"
    parent = self()

    runner =
      spawn(fn ->
        send(parent, {:runner_up, self()})
        Process.sleep(10_000)
      end)

    assert_receive {:runner_up, ^runner}, 500
    assert :ok = AgentRuns.try_start(chat, "kill", @msgs)
    assert :ok = AgentRuns.set_runner(chat, "kill", runner)
    assert {:ok, _} = AgentRuns.cancel(chat, "kill")
    refute Process.alive?(runner)
    assert :already_done = AgentRuns.finish(chat, "kill")
  end

  test "cancel with wrong run_id is ignore and does not free hub" do
    chat = "runtest01"
    assert :ok = AgentRuns.try_start(chat, "keep", @msgs)
    assert :ignore = AgentRuns.cancel(chat, "other")
    assert AgentRuns.active?(chat)
    assert AgentRuns.current_run(chat) == "keep"
    assert :ok = AgentRuns.finish(chat, "keep")
  end

  test "set_runner ignores stale run and accepts matching run" do
    chat = "runtest02"
    assert :ok = AgentRuns.try_start(chat, "r1", @msgs)
    assert :ignore = AgentRuns.set_runner(chat, "wrong", self())
    assert :ok = AgentRuns.set_runner(chat, "r1", self())
    live = AgentRuns.live_state(chat)
    assert live.runner_pid == self()
    assert :ok = AgentRuns.finish(chat, "r1")
    assert :ignore = AgentRuns.set_runner(chat, "r1", self())
  end

  test "cancel clears error flag on partial assistant" do
    chat = "runtest03"
    assert :ok = AgentRuns.try_start(chat, "err", @msgs)
    assert {:ok, _} = AgentRuns.append_token(chat, "err", "almost")
    # Simulate error content then cancel with partial still in hub after set_error
    assert {:ok, _} = AgentRuns.set_error(chat, "err", "Something went wrong")
    # Re-start isn't allowed while active — set_error keeps run active with is_loading false in snap
    # Cancel while still active should settle without error flag if content non-empty
    assert AgentRuns.active?(chat)
    assert {:ok, settled} = AgentRuns.cancel(chat, "err")
    last = List.last(settled)
    assert last.content == "Something went wrong"
    refute Map.get(last, :error)
  end

  test "mutations after cancel return ignore" do
    chat = "runtest01"
    assert :ok = AgentRuns.try_start(chat, "gone", @msgs)
    assert {:ok, _} = AgentRuns.cancel(chat, "gone")
    assert :ignore = AgentRuns.append_token(chat, "gone", "x")
    assert :ignore = AgentRuns.reset_assistant(chat, "gone")
    assert :ignore = AgentRuns.hold_draft(chat, "gone")
    assert :ignore = AgentRuns.set_status(chat, "gone", :generating)
    assert :ignore = AgentRuns.set_error(chat, "gone", "nope")
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
