defmodule AgentBackendWeb.BranchControllerTest do
  use AgentBackendWeb.ConnCase, async: false

  alias AgentBackend.ChatSessions

  import AgentBackend.TestHelpers

  test "GET /branch/:chat_id/:index forks prefix into new chat and redirects", %{conn: conn} do
    chat = unique_chat_id()

    history = [
      %{role: "user", content: "first question", timestamp: "t1"},
      %{role: "assistant", content: "first answer", timestamp: "t2"},
      %{role: "user", content: "second question", timestamp: "t3"},
      %{role: "assistant", content: "second answer", timestamp: "t4"}
    ]

    assert :ok = ChatSessions.save(chat, history)

    conn = get(conn, "/branch/#{chat}/1")
    assert redirected_to(conn) =~ ~r"^/c/[A-Za-z0-9]{6,12}$"

    new_id = redirected_to(conn) |> String.split("/") |> List.last()
    refute new_id == chat

    forked = ChatSessions.get(new_id).messages
    assert length(forked) == 2
    assert Enum.at(forked, 0).content == "first question"
    assert Enum.at(forked, 1).content == "first answer"

    # Original unchanged
    assert length(ChatSessions.get(chat).messages) == 4
  end

  test "branch on user turn includes history through that user", %{conn: conn} do
    chat = unique_chat_id()

    history = [
      %{role: "user", content: "q1", timestamp: "t1"},
      %{role: "assistant", content: "a1", timestamp: "t2"},
      %{role: "user", content: "q2", timestamp: "t3"},
      %{role: "assistant", content: "a2", timestamp: "t4"}
    ]

    assert :ok = ChatSessions.save(chat, history)

    conn = get(conn, "/branch/#{chat}/2")
    new_id = redirected_to(conn) |> String.split("/") |> List.last()

    forked = ChatSessions.get(new_id).messages
    assert Enum.map(forked, & &1.content) == ["q1", "a1", "q2"]
  end

  test "invalid index redirects back to source chat", %{conn: conn} do
    chat = unique_chat_id()

    assert :ok =
             ChatSessions.save(chat, [
               %{role: "user", content: "q", timestamp: "t1"},
               %{role: "assistant", content: "a", timestamp: "t2"}
             ])

    conn = get(conn, "/branch/#{chat}/99")
    assert redirected_to(conn) == "/c/#{chat}"
  end
end
