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
    |> form("#chat-form", %{message: "Where do you work?"})
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
      assert has_element?(view, "#chat-form")

      before = length(ChatSessions.get(chat).messages)

      view
      |> form("#chat-form", %{message: "second"})
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
    |> form("#chat-form", %{message: "trigger error"})
    |> render_submit()

    await_until(fn ->
      html = render(view)
      html =~ "Something went wrong on my side"
    end)
  end
end
