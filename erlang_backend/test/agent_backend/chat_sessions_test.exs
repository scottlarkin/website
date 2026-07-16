defmodule AgentBackend.ChatSessionsTest do
  use ExUnit.Case, async: false

  alias AgentBackend.ChatSessions

  setup do
    dir = Application.get_env(:agent_backend, :chat_sessions_dir)
    File.mkdir_p!(dir)

    on_exit(fn ->
      for path <- Path.wildcard(Path.join(dir, "*.json")) do
        File.rm(path)
      end
    end)

    :ok
  end

  test "valid_id?/1 accepts generated ids and rejects path traversal" do
    assert ChatSessions.valid_id?(ChatSessions.generate_id())
    assert ChatSessions.valid_id?("FlASWGHG")
    refute ChatSessions.valid_id?("../etc/passwd")
    refute ChatSessions.valid_id?("a")
    refute ChatSessions.valid_id?("has spaces")
    refute ChatSessions.valid_id?(nil)
  end

  test "save and get round-trip preserves messages" do
    id = ChatSessions.generate_id()

    messages = [
      %{role: "user", content: "hi", timestamp: "t1"},
      %{role: "assistant", content: "hello", timestamp: "t2"}
    ]

    assert :ok = ChatSessions.save(id, messages)
    assert %{messages: loaded} = ChatSessions.get(id)
    assert length(loaded) == 2
    assert Enum.at(loaded, 0).content == "hi"
    assert Enum.at(loaded, 1).content == "hello"
  end

  test "refuses empty overwrite of non-empty history" do
    id = ChatSessions.generate_id()

    assert :ok =
             ChatSessions.save(id, [
               %{role: "user", content: "keep me", timestamp: "t1"}
             ])

    assert {:error, :refuse_empty} = ChatSessions.save(id, [])
    assert %{messages: [msg]} = ChatSessions.get(id)
    assert msg.content == "keep me"
  end

  test "allows first save as empty list (new session)" do
    id = ChatSessions.generate_id()
    assert :ok = ChatSessions.save(id, [])
    assert %{messages: []} = ChatSessions.get(id)
  end

  test "put_slack_thread_ts preserves messages" do
    id = ChatSessions.generate_id()

    assert :ok =
             ChatSessions.save(id, [
               %{role: "user", content: "u", timestamp: "t"}
             ])

    assert :ok = ChatSessions.put_slack_thread_ts(id, "123.456")
    assert ChatSessions.get_slack_thread_ts(id) == "123.456"
    assert %{messages: [msg]} = ChatSessions.get(id)
    assert msg.content == "u"
  end

  test "concurrent save and put_slack do not lose either field" do
    id = ChatSessions.generate_id()
    assert :ok = ChatSessions.save(id, [%{role: "user", content: "start", timestamp: "t0"}])

    tasks =
      for i <- 1..20 do
        Task.async(fn ->
          if rem(i, 2) == 0 do
            ChatSessions.save(id, [
              %{role: "user", content: "u#{i}", timestamp: "t"},
              %{role: "assistant", content: "a#{i}", timestamp: "t"}
            ])
          else
            ChatSessions.put_slack_thread_ts(id, "ts.#{i}")
          end
        end)
      end

    Enum.each(tasks, &Task.await/1)

    %{messages: messages} = ChatSessions.get(id)
    ts = ChatSessions.get_slack_thread_ts(id)

    assert is_list(messages)
    assert messages != []
    assert is_binary(ts)
  end

  test "invalid id never writes under sessions dir" do
    dir = ChatSessions.sessions_dir()
    before = File.ls!(dir) |> MapSet.new()

    assert {:error, :invalid_id} = ChatSessions.save("../x", [%{role: "user", content: "nope"}])
    assert ChatSessions.get("../x") == %{messages: []}

    after_files = File.ls!(dir) |> MapSet.new()
    assert MapSet.equal?(before, after_files)
  end

  test "error flag round-trips on messages" do
    id = ChatSessions.generate_id()

    assert :ok =
             ChatSessions.save(id, [
               %{role: "assistant", content: "oops", timestamp: "t", error: true}
             ])

    assert %{messages: [msg]} = ChatSessions.get(id)
    assert msg.error == true
    assert msg.content == "oops"
  end

  test "atomic write leaves no tmp files" do
    id = ChatSessions.generate_id()
    dir = ChatSessions.sessions_dir()

    assert :ok = ChatSessions.save(id, [%{role: "user", content: "x", timestamp: "t"}])

    tmps = Path.wildcard(Path.join(dir, "#{id}.json.tmp*"))
    assert tmps == []
    assert File.exists?(Path.join(dir, "#{id}.json"))
  end

  test "ordered put_slack then save preserves both" do
    id = ChatSessions.generate_id()
    assert :ok = ChatSessions.put_slack_thread_ts(id, "thread.1")

    assert :ok =
             ChatSessions.save(id, [
               %{role: "user", content: "u", timestamp: "t"}
             ])

    assert ChatSessions.get_slack_thread_ts(id) == "thread.1"
    assert [%{content: "u"}] = ChatSessions.get(id).messages
  end
end
