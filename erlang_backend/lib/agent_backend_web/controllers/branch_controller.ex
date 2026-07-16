defmodule AgentBackendWeb.BranchController do
  @moduledoc """
  Forks a chat at a message index into a new session and redirects there.

  Uses a normal GET + redirect so `<a target="_blank">` opens a real new tab
  under the user gesture (popup blockers do not apply).
  """

  use Phoenix.Controller,
    namespace: AgentBackendWeb,
    formats: [html: Phoenix.View]

  import Plug.Conn
  import Phoenix.Controller

  alias AgentBackend.AgentRuns
  alias AgentBackend.ChatSessions

  def create(conn, %{"chat_id" => chat_id, "index" => index_param}) do
    with true <- ChatSessions.valid_id?(chat_id),
         {:ok, idx} <- parse_index(index_param),
         messages when is_list(messages) and messages != [] <- source_messages(chat_id),
         true <- idx < length(messages),
         forked when forked != [] <- fork_messages(messages, idx),
         new_id = ChatSessions.generate_id(),
         :ok <- ChatSessions.save(new_id, forked) do
      redirect(conn, to: "/c/#{new_id}")
    else
      _ ->
        fallback = if ChatSessions.valid_id?(chat_id), do: "/c/#{chat_id}", else: "/"
        redirect(conn, to: fallback)
    end
  end

  def create(conn, _params), do: redirect(conn, to: "/")

  defp parse_index(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_index(val) when is_integer(val) and val >= 0, do: {:ok, val}
  defp parse_index(_), do: :error

  defp source_messages(chat_id) do
    case AgentRuns.live_state(chat_id) do
      %{messages: msgs} when is_list(msgs) and msgs != [] -> msgs
      _ -> Map.get(ChatSessions.get(chat_id), :messages, [])
    end
  end

  defp fork_messages(messages, idx) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    messages
    |> Enum.take(idx + 1)
    |> Enum.map(&normalize_msg(&1, now))
    |> drop_empty_trailing_assistant()
  end

  defp normalize_msg(msg, default_ts) when is_map(msg) do
    base = %{
      role: to_string(Map.get(msg, :role) || Map.get(msg, "role") || "user"),
      content: to_string(Map.get(msg, :content) || Map.get(msg, "content") || ""),
      timestamp: to_string(Map.get(msg, :timestamp) || Map.get(msg, "timestamp") || default_ts)
    }

    if truthy?(Map.get(msg, :error) || Map.get(msg, "error")) do
      Map.put(base, :error, true)
    else
      base
    end
  end

  defp drop_empty_trailing_assistant(messages) do
    case List.last(messages) do
      %{role: "assistant", content: c, error: true} when c not in [nil, ""] ->
        messages

      %{role: "assistant", content: c} when c in [nil, ""] ->
        Enum.drop(messages, -1)

      _ ->
        messages
    end
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false
end
