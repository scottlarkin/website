defmodule AgentBackend.LLM.Fake do
  @moduledoc false

  @table :agent_backend_llm_fake

  def model, do: "fake/model"
  def validator_model, do: "fake/validator"

  def setup do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        :ok
    end

    reset()
  end

  def reset do
    ensure_table()
    :ets.insert(@table, {:stream_q, :queue.new()})
    :ets.insert(@table, {:complete_q, :queue.new()})
    :ets.insert(@table, {:calls, []})
  end

  @doc """
  Enqueue stream responses (FIFO). Each item is one of:
  - `{:ok, content}` when content is binary — emits on_token(content), returns ok map
  - `{:ok, content, chunks}` — emits each chunk then returns full content
  - `{:error, reason}`
  - `fn on_token -> result end` for full control
  """
  def push_stream(response) do
    ensure_table()
    q = :ets.lookup_element(@table, :stream_q, 2)
    :ets.insert(@table, {:stream_q, :queue.in(response, q)})
  end

  @doc """
  Enqueue complete/2 responses (FIFO):
  - `{:ok, content}`
  - `{:error, reason}`
  - binary (treated as {:ok, binary})
  """
  def push_complete(response) do
    ensure_table()
    q = :ets.lookup_element(@table, :complete_q, 2)
    :ets.insert(@table, {:complete_q, :queue.in(response, q)})
  end

  def calls do
    ensure_table()
    :ets.lookup_element(@table, :calls, 2) |> Enum.reverse()
  end

  def stream(messages, opts) do
    ensure_table()
    record({:stream, messages, opts})
    on_token = Keyword.fetch!(opts, :on_token)

    case pop(:stream_q) do
      nil ->
        {:error, "LLM.Fake: no stream script"}

      fun when is_function(fun, 1) ->
        fun.(on_token)

      fun when is_function(fun, 2) ->
        fun.(messages, on_token)

      {:ok, content, chunks} when is_list(chunks) ->
        Enum.each(chunks, on_token)
        {:ok, %{content: content, tool_calls: [], finish_reason: "stop"}}

      {:ok, content} when is_binary(content) ->
        if content != "", do: on_token.(content)
        {:ok, %{content: content, tool_calls: [], finish_reason: "stop"}}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, "LLM.Fake: bad stream script #{inspect(other)}"}
    end
  end

  def complete(messages, opts \\ []) do
    ensure_table()
    record({:complete, messages, opts})

    case pop(:complete_q) do
      nil ->
        # Default validator pass so happy-path tests only script streams
        {:ok, ~s({"passed": true})}

      {:ok, content} when is_binary(content) ->
        {:ok, content}

      {:error, reason} ->
        {:error, reason}

      content when is_binary(content) ->
        {:ok, content}

      fun when is_function(fun, 0) ->
        fun.()

      other ->
        {:error, "LLM.Fake: bad complete script #{inspect(other)}"}
    end
  end

  @doc "Stream call histories as recorded by stream/2 (oldest first)."
  def stream_calls do
    calls()
    |> Enum.filter(fn
      {:stream, _msgs, _opts} -> true
      {:stream, _opts} -> true
      _ -> false
    end)
  end

  @doc "Messages lists passed to stream/2 (oldest first)."
  def stream_message_histories do
    calls()
    |> Enum.flat_map(fn
      {:stream, msgs, _opts} when is_list(msgs) -> [msgs]
      _ -> []
    end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> setup()
      _ -> :ok
    end
  end

  defp pop(key) do
    q = :ets.lookup_element(@table, key, 2)

    case :queue.out(q) do
      {{:value, item}, q2} ->
        :ets.insert(@table, {key, q2})
        item

      {:empty, _} ->
        nil
    end
  end

  defp record(call) do
    calls = :ets.lookup_element(@table, :calls, 2)
    :ets.insert(@table, {:calls, [call | calls]})
  end
end
