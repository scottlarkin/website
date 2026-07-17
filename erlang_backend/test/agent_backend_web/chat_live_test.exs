defmodule AgentBackendWeb.ChatLiveTest do
  use AgentBackendWeb.LiveCase, async: false

  alias AgentBackend.AgentRuns
  alias AgentBackend.ChatSessions
  alias AgentBackend.LLM.Fake, as: LLM

  test "home page renders empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Hi, I&#39;m Scott." or html =~ "Hi, I'm Scott."
    assert html =~ "Skills"
  end

  test "send message completes with mocked LLM and persists", %{conn: conn} do
    LLM.push_stream({:ok, "I work at Ravio."})
    LLM.push_complete(~s({"passed": true}))

    {:ok, view, _html} = live(conn, "/")

    view
    |> form(~s(#chat-form), %{message: "Where do you work?"})
    |> render_submit()

    # Wait for agent task to persist
    await_until(fn ->
      # find any session with assistant content
      dir = Application.get_env(:agent_backend, :chat_sessions_dir)

      Enum.any?(Path.wildcard(Path.join(dir, "*.json")), fn path ->
        case File.read(path) do
          {:ok, body} ->
            case Jason.decode(body) do
              {:ok, %{"messages" => msgs}} ->
                Enum.any?(msgs, fn m ->
                  m["role"] == "assistant" and m["content"] == "I work at Ravio."
                end)

              _ ->
                false
            end

          _ ->
            false
        end
      end)
    end)

    html = render(view)
    assert html =~ "Ravio"
  end

  test "multi-line user message is preserved", %{conn: conn} do
    LLM.push_stream({:ok, "Got it."})
    LLM.push_complete(~s({"passed": true}))

    {:ok, view, html} = live(conn, "/")
    assert html =~ ~s(phx-hook="Composer") or html =~ "phx-hook=\"Composer\""
    assert html =~ "<textarea"

    multiline = "first line\nsecond line"

    view
    |> form(~s(#chat-form), %{message: multiline})
    |> render_submit()

    await_until(fn ->
      dir = Application.get_env(:agent_backend, :chat_sessions_dir)

      Enum.any?(Path.wildcard(Path.join(dir, "*.json")), fn path ->
        case File.read(path) do
          {:ok, body} ->
            case Jason.decode(body) do
              {:ok, %{"messages" => msgs}} ->
                Enum.any?(msgs, fn m ->
                  m["role"] == "user" and m["content"] == multiline
                end)

              _ ->
                false
            end

          _ ->
            false
        end
      end)
    end)

    rendered = render(view)
    assert rendered =~ "first line"
    assert rendered =~ "second line"
  end

  test "busy chat rejects second concurrent send", %{conn: conn} do
    chat = unique_chat_id()
    run = "busy-run"

    try do
      msgs = [
        %{role: "user", content: "first", timestamp: "t"},
        %{role: "assistant", content: "", timestamp: "t"}
      ]

      assert :ok = AgentRuns.try_start(chat, run, msgs)
      assert :ok = ChatSessions.save(chat, msgs)

      {:ok, view, _html} = live(conn, "/c/#{chat}")
      assert has_element?(view, ~s(#chat-form))

      before = length(ChatSessions.get(chat).messages)

      view
      |> form(~s(#chat-form), %{message: "second"})
      |> render_submit()

      Process.sleep(50)
      assert length(ChatSessions.get(chat).messages) == before
    after
      finish_run(chat)
    end
  end

  test "mid-stream join loads live hub state", %{conn: conn} do
    chat = unique_chat_id()
    run = "join-run"

    try do
      msgs = [
        %{role: "user", content: "hello", timestamp: "t"},
        %{role: "assistant", content: "", timestamp: "t"}
      ]

      assert :ok = AgentRuns.try_start(chat, run, msgs)
      assert {:ok, _} = AgentRuns.append_token(chat, run, "Partial answer")
      assert :ok = ChatSessions.save(chat, msgs)

      {:ok, _view, html} = live(conn, "/c/#{chat}")
      assert html =~ "Partial answer"
    after
      finish_run(chat)
    end
  end

  test "invalid chat id does not crash", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/c/bad")
    # treated as empty home-like chat without id semantics
    assert html =~ "Scott" or html =~ "Message"
  end

  test "error path shows generic error copy", %{conn: conn} do
    LLM.push_stream({:error, "boom"})
    LLM.push_complete({:error, "still boom"})

    {:ok, view, _html} = live(conn, "/")

    view
    |> form(~s(#chat-form), %{message: "trigger error"})
    |> render_submit()

    await_until(fn ->
      html = render(view)
      html =~ "Something went wrong on my side"
    end)
  end

  test "cancel_run stops generation and keeps partial", %{conn: conn} do
    LLM.push_stream(fn on_token ->
      on_token.("Partial answer")
      Process.sleep(15_000)
      {:ok, %{content: "Partial answer full", tool_calls: [], finish_reason: "stop"}}
    end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> form(~s(#chat-form), %{message: "tell me something"})
    |> render_submit()

    await_until(fn ->
      html = render(view)
      html =~ "Partial answer" and html =~ ~s(id="cancel-run-btn")
    end)

    chat_id = chat_id_from_view(view)
    assert is_binary(chat_id)
    assert AgentRuns.active?(chat_id)

    view |> element("#cancel-run-btn") |> render_click()

    await_until(fn ->
      html = render(view)
      html =~ "Partial answer" and not (html =~ ~s(id="cancel-run-btn"))
    end)

    refute AgentRuns.active?(chat_id)

    # Disk keeps partial, not the would-be full completion
    msgs = ChatSessions.get(chat_id).messages
    assert List.last(msgs).content == "Partial answer"
    refute Map.get(List.last(msgs), :error)

    # Late fake stream must not overwrite partial (runner killed / finish claimed)
    Process.sleep(50)
    assert List.last(ChatSessions.get(chat_id).messages).content == "Partial answer"

    # Single-flight free: a new send should work
    LLM.push_stream({:ok, "Second reply"})
    LLM.push_complete(~s({"passed": true}))

    view
    |> form(~s(#chat-form), %{message: "another question"})
    |> render_submit()

    await_until(fn ->
      render(view) =~ "Second reply"
    end)
  end

  test "cancel_run with no tokens drops empty assistant from disk", %{conn: conn} do
    LLM.push_stream(fn _on_token ->
      Process.sleep(15_000)
      {:ok, %{content: "late full", tool_calls: [], finish_reason: "stop"}}
    end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> form(~s(#chat-form), %{message: "will cancel empty"})
    |> render_submit()

    await_until(fn ->
      render(view) =~ ~s(id="cancel-run-btn")
    end)

    chat_id = chat_id_from_view(view)
    assert is_binary(chat_id)

    view |> element("#cancel-run-btn") |> render_click()

    await_until(fn ->
      not (render(view) =~ ~s(id="cancel-run-btn")) and not AgentRuns.active?(chat_id)
    end)

    msgs = ChatSessions.get(chat_id).messages
    assert length(msgs) == 1
    assert hd(msgs).role == "user"
    assert hd(msgs).content == "will cancel empty"
    refute Enum.any?(msgs, &(&1.role == "assistant"))
  end

  test "cancel_run is no-op when idle", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    html_before = render(view)
    render_click(view, "cancel_run", %{})
    assert render(view) == html_before
  end

  test "reload_message only allowed on last assistant; mid-thread is no-op", %{conn: conn} do
    chat = unique_chat_id()

    history = [
      %{role: "user", content: "first question", timestamp: "t1"},
      %{role: "assistant", content: "first answer", timestamp: "t2"},
      %{role: "user", content: "second question", timestamp: "t3"},
      %{role: "assistant", content: "second answer", timestamp: "t4"}
    ]

    assert :ok = ChatSessions.save(chat, history)

    {:ok, view, html} = live(conn, "/c/#{chat}")
    assert html =~ "first answer"
    assert html =~ "second answer"
    # Reload control only on last assistant
    refute has_element?(view, ~s(button[phx-click="reload_message"][phx-value-index="1"]))
    assert has_element?(view, ~s(button[phx-click="reload_message"][phx-value-index="3"]))
    # Branch is a real new-tab link (not LiveView) on earlier messages
    assert has_element?(view, ~s(a[href="/branch/#{chat}/1"][target="_blank"]))

    # Event-level guard: mid-thread reload must not mutate history
    render_click(view, "reload_message", %{"index" => "1"})
    Process.sleep(40)

    msgs = ChatSessions.get(chat).messages
    assert length(msgs) == 4
    assert Enum.at(msgs, 1).content == "first answer"
    assert Enum.at(msgs, 3).content == "second answer"
    refute AgentRuns.active?(chat)
  end

  test "reload_message on last assistant replaces only that reply", %{conn: conn} do
    chat = unique_chat_id()

    history = [
      %{role: "user", content: "q1", timestamp: "t1"},
      %{role: "assistant", content: "a1", timestamp: "t2"},
      %{role: "user", content: "q2", timestamp: "t3"},
      %{role: "assistant", content: "a2", timestamp: "t4"}
    ]

    assert :ok = ChatSessions.save(chat, history)

    LLM.push_stream({:ok, "a2 regenerated"})
    LLM.push_complete(~s({"passed": true}))

    {:ok, view, _html} = live(conn, "/c/#{chat}")

    view
    |> element(~s(button[phx-click="reload_message"][phx-value-index="3"]))
    |> render_click()

    await_until(fn ->
      msgs = ChatSessions.get(chat).messages
      length(msgs) == 4 and List.last(msgs).content == "a2 regenerated"
    end)

    msgs = ChatSessions.get(chat).messages
    assert Enum.at(msgs, 0).content == "q1"
    assert Enum.at(msgs, 1).content == "a1"
    assert Enum.at(msgs, 2).content == "q2"
    assert Enum.at(msgs, 3).content == "a2 regenerated"
    assert render(view) =~ "a2 regenerated"
  end

  test "branch link is present only on agent messages when chat has an id", %{conn: conn} do
    chat = unique_chat_id()

    history = [
      %{role: "user", content: "q1", timestamp: "t1"},
      %{role: "assistant", content: "a1", timestamp: "t2"}
    ]

    assert :ok = ChatSessions.save(chat, history)
    {:ok, view, _html} = live(conn, "/c/#{chat}")

    # User turns: no branch control
    refute has_element?(view, ~s(a[href="/branch/#{chat}/0"][target="_blank"]))
    # Assistant turns: branch link opens in a new tab
    assert has_element?(view, ~s(a[href="/branch/#{chat}/1"][target="_blank"]))
  end

  test "reload_message while busy is no-op", %{conn: conn} do
    chat = unique_chat_id()
    run = "reload-busy"

    history = [
      %{role: "user", content: "q", timestamp: "t1"},
      %{role: "assistant", content: "a", timestamp: "t2"}
    ]

    try do
      assert :ok = ChatSessions.save(chat, history)

      ui =
        history ++
          [%{role: "user", content: "pending", timestamp: "t3"}, %{role: "assistant", content: "", timestamp: "t4"}]

      assert :ok = AgentRuns.try_start(chat, run, ui)

      {:ok, view, _html} = live(conn, "/c/#{chat}")
      before = ChatSessions.get(chat).messages

      render_click(view, "reload_message", %{"index" => "1"})
      Process.sleep(40)

      # Busy single-flight: disk unchanged, hub still active for original run
      assert AgentRuns.active?(chat)
      assert AgentRuns.current_run(chat) == run
      assert ChatSessions.get(chat).messages == before
    after
      finish_run(chat)
    end
  end

  test "reload_message with invalid index is no-op", %{conn: conn} do
    chat = unique_chat_id()

    history = [
      %{role: "user", content: "q", timestamp: "t1"},
      %{role: "assistant", content: "a", timestamp: "t2"}
    ]

    assert :ok = ChatSessions.save(chat, history)
    {:ok, view, _html} = live(conn, "/c/#{chat}")

    render_click(view, "reload_message", %{"index" => "99"})
    render_click(view, "reload_message", %{"index" => "0"})
    render_click(view, "reload_message", %{"index" => "nope"})

    Process.sleep(30)
    msgs = ChatSessions.get(chat).messages
    assert length(msgs) == 2
    assert List.last(msgs).content == "a"
    refute AgentRuns.active?(chat)
  end

  test "reload after error regenerates reply", %{conn: conn} do
    LLM.push_stream({:error, "boom"})
    LLM.push_complete({:error, "still boom"})

    {:ok, view, _html} = live(conn, "/")

    view
    |> form(~s(#chat-form), %{message: "trigger error for reload"})
    |> render_submit()

    await_until(fn ->
      render(view) =~ "Something went wrong on my side"
    end)

    chat_id = chat_id_from_view(view)
    assert is_binary(chat_id)

    LLM.push_stream({:ok, "recovered answer"})
    LLM.push_complete(~s({"passed": true}))

    view
    |> element(~s(button[phx-click="reload_message"]))
    |> render_click()

    await_until(fn ->
      render(view) =~ "recovered answer"
    end)

    last = List.last(ChatSessions.get(chat_id).messages)
    assert last.content == "recovered answer"
    refute Map.get(last, :error)
  end

  test "composer has stable form id and phx-change for reconnect recovery", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ ~s(id="chat-form")
    assert html =~ ~s(phx-change="update_input")
    assert html =~ ~s(id="message")
    refute html =~ ~s(id="chat-form-0")
  end

  test "composer draft is kept on phx-change and cleared after send", %{conn: conn} do
    LLM.push_stream({:ok, "ok"})
    LLM.push_complete(~s({"passed": true}))

    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("#chat-form", %{message: "half typed draft"})
      |> render_change()

    assert html =~ ~r/<textarea[^>]*id="message"[^>]*>half typed draft<\/textarea>/

    view
    |> form("#chat-form", %{message: "half typed draft"})
    |> render_submit()

    await_until(fn ->
      render(view) =~ "ok"
    end)

    html = render(view)
    # User message stays in the transcript; only the composer draft is cleared.
    assert html =~ "half typed draft"
    assert html =~ ~r/<textarea[^>]*id="message"[^>]*>\s*<\/textarea>/
  end

  defp chat_id_from_view(view) do
    html = render(view)

    case Regex.run(~r/data-copy-url="[^"]*\/c\/([A-Za-z0-9]+)"/, html) do
      [_, id] -> id
      _ -> nil
    end
  end
end
