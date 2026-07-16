defmodule AgentBackend.TestHelpers do
  @moduledoc false

  import ExUnit.Assertions

  alias AgentBackend.AgentRuns
  alias AgentBackend.ChatSessions
  alias AgentBackend.LLM.Fake, as: LLMFake
  alias AgentBackend.Slack.Fake, as: SlackFake

  def setup_fakes do
    LLMFake.setup()
    SlackFake.setup()
    :ok
  end

  def unique_chat_id do
    ChatSessions.generate_id()
  end

  def finish_run(chat_id) do
    case AgentRuns.current_run(chat_id) do
      nil -> :ok
      rid -> AgentRuns.finish(chat_id, rid)
    end
  end

  def recorder do
    {:ok, pid} = Agent.start_link(fn -> [] end)

    callbacks = %{
      on_token: fn t -> Agent.update(pid, &[{:token, t} | &1]) end,
      on_reset: fn -> Agent.update(pid, &[:reset | &1]) end,
      on_hold_draft: fn -> Agent.update(pid, &[:hold_draft | &1]) end,
      on_status: fn s -> Agent.update(pid, &[{:status, s} | &1]) end,
      on_done: fn m -> Agent.update(pid, &[{:done, m} | &1]) end,
      on_error: fn e -> Agent.update(pid, &[{:error, e} | &1]) end
    }

    {pid, callbacks}
  end

  def events(pid) do
    Agent.get(pid, &Enum.reverse/1)
  end

  def await_until(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2_000)
    interval = Keyword.get(opts, :interval, 20)
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      if fun.() do
        :ok
      else
        if System.monotonic_time(:millisecond) > deadline do
          flunk("await_until timed out")
        end

        Process.sleep(interval)
        :retry
      end
    end)
    |> Enum.find(&(&1 == :ok))
  end

  def last_assistant_content(chat_id) do
    case ChatSessions.get(chat_id).messages |> List.last() do
      %{role: "assistant", content: c} -> c
      _ -> nil
    end
  end
end
