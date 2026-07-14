defmodule AgentBackend.Slack do
  @moduledoc """
  Thin Slack Web API client for chat.postMessage.
  """

  @api_url "https://slack.com/api/chat.postMessage"
  @max_text_length 3000

  def enabled? do
    bot_token() != nil and monitor_channel() != nil
  end

  def errors_enabled? do
    bot_token() != nil and errors_channel() != nil
  end

  def monitor_channel, do: env("SLACK_MONITOR_CHANNEL_ID")
  def errors_channel, do: env("SLACK_ERRORS_CHANNEL_ID")

  def chat_url(chat_id) when is_binary(chat_id) do
    host = System.get_env("PHX_HOST")

    if is_binary(host) and host != "" do
      "https://#{host}/c/#{chat_id}"
    else
      port = System.get_env("PORT", "3000")
      "http://localhost:#{port}/c/#{chat_id}"
    end
  end

  def post_message(channel, text, opts \\ []) when is_binary(channel) and is_binary(text) do
    token = bot_token()

    if token == nil do
      {:error, :not_configured}
    else
      body =
        %{
          channel: channel,
          text: truncate(text),
          unfurl_links: false,
          unfurl_media: false
        }
        |> maybe_put(:thread_ts, Keyword.get(opts, :thread_ts))

      try do
        case Req.post(@api_url,
               headers: [
                 {"authorization", "Bearer #{token}"},
                 {"content-type", "application/json"}
               ],
               json: body,
               receive_timeout: 15_000
             ) do
          {:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}} when is_binary(ts) ->
            {:ok, ts}

          {:ok, %{body: %{"ok" => false, "error" => error}}} ->
            log_failure("Slack API error: #{error}")
            {:error, error}

          {:ok, resp} ->
            log_failure("Slack unexpected response: #{inspect(resp.status)} #{inspect(resp.body)}")
            {:error, :unexpected_response}

          {:error, reason} ->
            log_failure("Slack request failed: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        e ->
          log_failure("Slack request crashed: #{Exception.message(e)}")
          {:error, e}
      end
    end
  end

  defp bot_token, do: env("SLACK_BOT_TOKEN")

  defp env(key) do
    case System.get_env(key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value != "", do: value, else: nil

      _ ->
        nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp truncate(text) when byte_size(text) <= @max_text_length, do: text

  defp truncate(text) do
    String.slice(text, 0, @max_text_length) <> "…"
  end

  defp log_failure(message) do
    require Logger
    Logger.warning(message)
  end
end