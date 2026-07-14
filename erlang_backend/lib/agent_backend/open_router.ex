defmodule AgentBackend.OpenRouter do
  @moduledoc """
  OpenRouter chat completions client (streaming + non-streaming).
  """

  @api_url "https://openrouter.ai/api/v1/chat/completions"
  @default_model "nvidia/nemotron-3-ultra-550b-a55b:free"

  def model do
    env_model("OPENROUTER_MODEL") || @default_model
  end

  def validator_model do
    env_model("OPENROUTER_VALIDATOR_MODEL") || model()
  end

  defp env_model(key) do
    case System.get_env(key) do
      m when is_binary(m) ->
        m = String.trim(m)
        if m != "", do: m, else: nil

      _ ->
        nil
    end
  end

  def stream(messages, opts) do
    api_key = api_key()

    if api_key == nil do
      {:error, "OPENROUTER_KEY not set in environment."}
    else
      on_token = Keyword.fetch!(opts, :on_token)
      tools = Keyword.get(opts, :tools, [])

      body =
        %{
          model: model(),
          messages: messages,
          stream: true,
          temperature: Keyword.get(opts, :temperature, 0.4)
        }
        |> maybe_put_tools(tools)

      try do
        started_at = System.monotonic_time(:millisecond)

        case Req.post(@api_url,
               headers: headers(),
               json: body,
               into: :self,
               receive_timeout: 300_000
             ) do
          {:ok, resp} ->
            if resp.status != 200 do
              {:error, format_http_error(resp)}
            else
              consume_stream(resp, on_token, started_at)
            end

          {:error, reason} ->
            {:error, "LLM stream request failed: #{inspect(reason)}"}
        end
      rescue
        e -> {:error, "LLM stream failed: #{Exception.message(e)}"}
      end
    end
  end

  def complete(messages, opts \\ []) do
    api_key = api_key()

    if api_key == nil do
      {:error, "OPENROUTER_KEY not set in environment."}
    else
      body =
        %{
          model: Keyword.get(opts, :model, model()),
          messages: messages,
          stream: false,
          temperature: Keyword.get(opts, :temperature, 0.2)
        }
        |> maybe_put(:max_tokens, Keyword.get(opts, :max_tokens))

      try do
        resp =
          Req.post!(@api_url,
            headers: headers(),
            json: body,
            receive_timeout: 120_000
          )

        case resp.body do
          %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
            {:ok, content}

          %{"error" => error} ->
            {:error, "LLM Error: #{inspect(error)}"}

          other ->
            {:error, "unexpected completion response: #{inspect(other)}"}
        end
      rescue
        e -> {:error, "LLM completion failed: #{Exception.message(e)}"}
      end
    end
  end

  defp consume_stream(resp, on_token, started_at) do
    state = %{
      content: "",
      tool_calls: %{},
      finish_reason: nil,
      error: nil,
      chunks: 0,
      started_at: started_at,
      ttft_logged: false
    }

    consume = fn consume, state ->
      case Req.parse_message(resp, receive do m -> m end) do
        {:ok, [{:data, data}]} ->
          state =
            state
            |> Map.update!(:chunks, &(&1 + 1))
            |> then(fn s -> process_sse_data(data, on_token, s) end)

          if state.error, do: state, else: consume.(consume, state)

        {:ok, [:done]} ->
          state

        {:ok, _other} ->
          consume.(consume, state)

        {:error, reason} ->
          %{state | error: "stream parse error: #{inspect(reason)}"}
      end
    end

    state = consume.(consume, state)

    cond do
      state.error ->
        {:error, state.error}

      state.content != "" or state.tool_calls != %{} ->
        {:ok,
         %{
           content: state.content,
           tool_calls: tool_calls_list(state.tool_calls),
           finish_reason: state.finish_reason
         }}

      true ->
        require Logger
        Logger.warning("OpenRouter stream empty chunks=#{state.chunks} finish=#{inspect(state.finish_reason)} model=#{model()}")

        {:error, "Empty stream from OpenRouter (model=#{model()})"}
    end
  end

  defp format_http_error(resp) do
    body =
      case resp.body do
        b when is_binary(b) -> b
        b when is_map(b) -> Jason.encode!(b)
        other -> inspect(other)
      end

    "OpenRouter HTTP #{resp.status}: #{String.slice(body, 0, 500)}"
  end

  defp api_key do
    case System.get_env("OPENROUTER_KEY") do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end

  defp headers do
    port = System.get_env("PORT", "3001")
    host = System.get_env("PHX_URL_HOST", "localhost")

    [
      {"Authorization", "Bearer #{api_key()}"},
      {"HTTP-Referer", "http://#{host}:#{port}"},
      {"X-Title", "Personal Agent"}
    ]
  end

  defp maybe_put(body, _key, nil), do: body
  defp maybe_put(body, key, val), do: Map.put(body, key, val)

  defp maybe_put_tools(body, []), do: body
  defp maybe_put_tools(body, tools), do: Map.put(body, :tools, tools)

  defp process_sse_data(data, on_token, state) do
    data
    |> String.split("\n")
    |> Enum.reduce(state, fn line, acc ->
      line = String.trim(line)

      cond do
        String.starts_with?(line, "data: [DONE]") ->
          acc

        String.starts_with?(line, "data: ") ->
          json_str = String.trim_leading(line, "data: ") |> String.trim()
          parse_sse_json(json_str, on_token, acc)

        true ->
          acc
      end
    end)
  end

  defp parse_sse_json("", _on_token, acc), do: acc
  defp parse_sse_json("[DONE]", _on_token, acc), do: acc

  defp parse_sse_json(json_str, on_token, acc) do
    case Jason.decode(json_str) do
      {:ok, %{"choices" => [choice | _]}} ->
        delta = Map.get(choice, "delta", %{})
        finish = Map.get(choice, "finish_reason")

        acc =
          acc
          |> append_content(delta, on_token)
          |> merge_tool_calls(delta)
          |> put_finish_reason(finish)

        acc

      {:ok, %{"error" => error}} ->
        %{acc | error: "LLM Error: #{inspect(error)}"}

      {:ok, decoded} ->
        require Logger
        Logger.debug("OpenRouter unhandled SSE JSON: #{inspect(decoded)}")
        acc

      {:error, reason} ->
        %{acc | error: "SSE JSON decode error: #{inspect(reason)}"}
    end
  end

  defp append_content(acc, %{"content" => content}, on_token)
       when is_binary(content) and content != "" do
    acc = log_ttft(acc)
    on_token.(content)
    %{acc | content: acc.content <> content}
  end

  defp append_content(acc, %{"text" => text}, on_token) when is_binary(text) and text != "" do
    acc = log_ttft(acc)
    on_token.(text)
    %{acc | content: acc.content <> text}
  end

  defp append_content(acc, _, _on_token), do: acc

  defp log_ttft(%{ttft_logged: true} = acc), do: acc

  defp log_ttft(acc) do
    require Logger
    ttft = System.monotonic_time(:millisecond) - acc.started_at
    Logger.info("OpenRouter TTFT=#{ttft}ms model=#{model()}")
    %{acc | ttft_logged: true}
  end

  defp merge_tool_calls(acc, %{"tool_calls" => calls}) when is_list(calls) do
    merged =
      Enum.reduce(calls, acc.tool_calls, fn call, tool_acc ->
        index = Map.get(call, "index", 0)
        existing = Map.get(tool_acc, index, %{id: nil, name: nil, arguments: ""})

        updated =
          existing
          |> maybe_put(:id, call["id"])
          |> maybe_put(:name, get_in(call, ["function", "name"]))
          |> append_arguments(get_in(call, ["function", "arguments"]))

        Map.put(tool_acc, index, updated)
      end)

    %{acc | tool_calls: merged}
  end

  defp merge_tool_calls(acc, _), do: acc

  defp append_arguments(existing, arg) when is_binary(arg) do
    %{existing | arguments: existing.arguments <> arg}
  end

  defp append_arguments(existing, _), do: existing

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp put_finish_reason(acc, finish) when is_binary(finish), do: %{acc | finish_reason: finish}
  defp put_finish_reason(acc, _), do: acc

  defp tool_calls_list(tool_calls_map) do
    tool_calls_map
    |> Enum.sort_by(fn {index, _} -> index end)
    |> Enum.map(fn {_index, %{id: id, name: name, arguments: args}} ->
      %{
        id: id || "call_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false),
        name: name,
        arguments: parse_arguments(args)
      }
    end)
    |> Enum.filter(&(&1.name != nil))
  end

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_arguments(_), do: %{}
end