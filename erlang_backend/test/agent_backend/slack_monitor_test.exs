defmodule AgentBackend.SlackMonitorTest do
  use ExUnit.Case, async: false

  alias AgentBackend.ChatSessions
  alias AgentBackend.Slack.Fake, as: SlackFake
  alias AgentBackend.SlackMonitor
  alias AgentBackend.TestHelpers

  setup do
    TestHelpers.setup_fakes()
    chat = TestHelpers.unique_chat_id()
    :ok = ChatSessions.save(chat, [])
    {:ok, chat: chat}
  end

  test "user message creates parent thread then replies", %{chat: chat} do
    SlackMonitor.log_user_message(chat, "hello")
    SlackMonitor.sync()

    posts = SlackFake.posts()
    assert length(posts) == 2
    [parent, reply] = posts
    assert parent.channel == "C_MONITOR"
    assert parent.thread_ts == nil
    assert parent.text =~ chat
    assert reply.thread_ts == parent.ts
    assert reply.text =~ "hello"
    assert ChatSessions.get_slack_thread_ts(chat) == parent.ts
  end

  test "second user message only posts in existing thread", %{chat: chat} do
    SlackMonitor.log_user_message(chat, "one")
    SlackMonitor.sync()
    SlackMonitor.log_user_message(chat, "two")
    SlackMonitor.sync()

    posts = SlackFake.posts()
    assert length(posts) == 3
    parent_ts = hd(posts).ts
    assert Enum.at(posts, 2).thread_ts == parent_ts
    assert Enum.at(posts, 2).text =~ "two"
  end

  test "assistant message posts to thread", %{chat: chat} do
    SlackMonitor.log_user_message(chat, "q")
    SlackMonitor.sync()
    SlackMonitor.log_assistant_message(chat, "answer")
    SlackMonitor.sync()

    assert Enum.any?(SlackFake.posts(), &(&1.text =~ "answer"))
  end

  test "error posts to errors channel", %{chat: chat} do
    SlackMonitor.log_error(chat, :timeout, "took too long")
    SlackMonitor.sync()

    [post] = SlackFake.posts()
    assert post.channel == "C_ERRORS"
    assert post.text =~ "timeout"
    assert post.text =~ "took too long"
  end

  test "disabled slack posts nothing", %{chat: chat} do
    SlackFake.set_enabled(false)
    SlackFake.set_errors_enabled(false)
    SlackMonitor.log_user_message(chat, "hi")
    SlackMonitor.log_error(chat, :crash, "x")
    SlackMonitor.sync()
    assert SlackFake.posts() == []
  end
end
