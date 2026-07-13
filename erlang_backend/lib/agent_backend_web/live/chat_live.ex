defmodule AgentBackendWeb.ChatLive do
  use AgentBackendWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]

  # Load .env if present (for OPENROUTER_KEY and SYSTEM_PROMPT)
  # Looks for .env in current or parent directories (works when starting from erlang_backend/)
  # Supports multiline quoted values (e.g. SYSTEM_PROMPT="... \n ...")
  defp load_env do
    candidates = [
      Path.join(File.cwd!(), ".env"),
      Path.join(File.cwd!(), "../.env"),
      Path.join(File.cwd!(), "../../.env")
    ]

    env_file =
      candidates
      |> Enum.map(&Path.expand/1)
      |> Enum.find(&File.exists?/1)

    if env_file do
      content = File.read!(env_file)

      # Quoted values (multiline supported inside "...")
      quoted_envs =
        Regex.scan(~r/([A-Za-z0-9_]+)\s*=\s*"([\s\S]*?)"/, content, capture: :all_but_first)
        |> Enum.into(%{}, fn [k, v] -> {k, String.trim(v)} end)

      # Simple unquoted or single-line quoted KEY=val
      simple_matches = Regex.scan(~r/^([A-Za-z0-9_]+)\s*=\s*(?:"([^"]*)"|([^"\n]*))$/m, content, capture: :all_but_first)
      simple_envs =
        simple_matches
        |> Enum.map(fn
          [k, "", val] -> {k, String.trim(val)}
          [k, val, ""] -> {k, String.trim(val)}
          [k, val, _] -> {k, String.trim(val)}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.into(%{})

      envs = Map.merge(simple_envs, quoted_envs)

      Enum.each(envs, fn {key, value} ->
        # Only set if not already in OS env (OS env takes precedence)
        if System.get_env(key) in [nil, ""] do
          System.put_env(key, value)
        end
      end)

      require Logger
      Logger.info("System prompt loaded, length=#{AgentBackend.SystemPrompt.char_count()} chars")
    end
  end

  @impl true
  def mount(params, _session, socket) do
    load_env()

    chat_id = params["id"]
    messages = load_chat_messages(chat_id)

    socket =
      socket
      |> assign(
        messages: messages,
        input: "",
        is_loading: false,
        chat_id: chat_id,
        suggestions: [
          "What are your technical skills?",
          "Tell me about your education",
          "What projects have you worked on?",
          "What is your experience?",
          "How can I contact you?"
        ],
        page_title: "Chat"
      )
      |> subscribe_chat(chat_id)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    old_chat_id = socket.assigns[:chat_id]
    chat_id = params["id"]

    messages =
      cond do
        is_nil(chat_id) and is_binary(old_chat_id) ->
          # Reconnect join URL can lag behind browser URL — keep active session
          socket.assigns.messages

        is_nil(chat_id) ->
          []

        chat_id == old_chat_id and socket.assigns.messages != [] ->
          # Same id with an active session (e.g. streaming) — keep in-memory state
          socket.assigns.messages

        true ->
          load_chat_messages(chat_id)
      end

    socket =
      socket
      |> unsubscribe_chat(old_chat_id)
      |> subscribe_chat(chat_id)
      |> assign(chat_id: chat_id, messages: messages)

    {:noreply, socket}
  end

  defp load_chat_messages(nil), do: []

  defp load_chat_messages(chat_id) when is_binary(chat_id) do
    AgentBackend.ChatSessions.get(chat_id) |> Map.get(:messages, [])
  end

  defp chat_topic(chat_id) when is_binary(chat_id), do: "chat:#{chat_id}"

  defp subscribe_chat(socket, nil), do: socket

  defp subscribe_chat(socket, chat_id) when is_binary(chat_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentBackend.PubSub, chat_topic(chat_id))
    end

    socket
  end

  defp unsubscribe_chat(socket, nil), do: socket

  defp unsubscribe_chat(socket, chat_id) when is_binary(chat_id) do
    if connected?(socket) do
      Phoenix.PubSub.unsubscribe(AgentBackend.PubSub, chat_topic(chat_id))
    end

    socket
  end

  defp broadcast_chat_sync(socket, messages, is_loading) do
    if chat_id = socket.assigns.chat_id do
      Phoenix.PubSub.broadcast_from(
        AgentBackend.PubSub,
        self(),
        chat_topic(chat_id),
        {:chat_sync, %{messages: messages, is_loading: is_loading}}
      )
    end

    socket
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    {:noreply,
     socket
     |> assign(messages: [], input: "", chat_id: nil, is_loading: false)
     |> Phoenix.LiveView.push_navigate(to: "/")}
  end

  @impl true
  def handle_event("send_message", params, socket) do
    message = Map.get(params, "message", Map.get(params, "input", ""))
    do_send_message(message, socket)
  end

  @impl true
  def handle_event("update_input", params, socket) do
    # Can come as the field name or as "value" depending on whether phx-change is on form or input
    input =
      Map.get(params, "message") ||
        Map.get(params, "input") ||
        Map.get(params, "value") ||
        ""
    {:noreply, assign(socket, input: input)}
  end

  # Allow clicking a suggestion to send it directly
  @impl true
  def handle_event("send_suggestion", %{"message" => message}, socket) do
    do_send_message(message, socket)
  end

  defp do_send_message(raw_message, socket) do
    message = String.trim(raw_message)
    if message == "" or socket.assigns.is_loading do
      {:noreply, socket}
    else
      user_msg = %{
        role: "user",
        content: message,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      user_messages = socket.assigns.messages ++ [user_msg]

      # Add empty assistant placeholder so the bubble appears immediately for streaming
      assistant = %{
        role: "assistant",
        content: "",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      ui_messages = user_messages ++ [assistant]

      # Generate (or keep) a shareable chat id when the chat actually starts.
      # Capture the *old* value before we assign, so the patch condition works.
      old_chat_id = socket.assigns[:chat_id]
      chat_id = old_chat_id || AgentBackend.ChatSessions.generate_id()

      # Persist immediately (at least the user message + placeholder)
      AgentBackend.ChatSessions.save(chat_id, ui_messages)

      # Update local state
      socket =
        socket
        |> unsubscribe_chat(old_chat_id)
        |> subscribe_chat(chat_id)
        |> assign(messages: ui_messages, is_loading: true, input: "", chat_id: chat_id)
        |> broadcast_chat_sync(ui_messages, true)

      # First message: sync URL to /c/:id without remounting (push_patch, not push_navigate).
      socket =
        if is_nil(old_chat_id) do
          Phoenix.LiveView.push_patch(socket, to: "/c/#{chat_id}", replace: true)
        else
          socket
        end

      lv_pid = self()

      Task.start(fn ->
        system_prompt = AgentBackend.SystemPrompt.load()
        require Logger
        Logger.info("Starting LLM stream for: #{inspect(message)} (id=#{chat_id})")
        stream_llm(user_messages, system_prompt, lv_pid)
      end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_token, token}, socket) do
    messages = socket.assigns.messages

    if messages != [] do
      last_idx = length(messages) - 1
      last = List.last(messages)

      if last && last.role == "assistant" do
        updated = %{last | content: last.content <> token}
        messages = List.replace_at(messages, last_idx, updated)

        # Persist partial state so reload during streaming keeps progress
        if chat_id = socket.assigns.chat_id do
          AgentBackend.ChatSessions.save(chat_id, messages)
        end

        socket =
          socket
          |> assign(messages: messages)
          |> broadcast_chat_sync(messages, true)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:stream_done, socket) do
    # Ensure the final state is saved
    if chat_id = socket.assigns.chat_id do
      AgentBackend.ChatSessions.save(chat_id, socket.assigns.messages)
    end

    socket =
      socket
      |> assign(is_loading: false)
      |> broadcast_chat_sync(socket.assigns.messages, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_error, error_msg}, socket) do
    messages = socket.assigns.messages

    if messages != [] do
      last_idx = length(messages) - 1
      last = List.last(messages)

      if last && last.role == "assistant" do
        updated = %{last | content: error_msg}
        messages = List.replace_at(messages, last_idx, updated)

        if chat_id = socket.assigns.chat_id do
          AgentBackend.ChatSessions.save(chat_id, messages)
        end

        socket =
          socket
          |> assign(messages: messages, is_loading: false)
          |> broadcast_chat_sync(messages, false)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:chat_sync, %{messages: messages, is_loading: is_loading}}, socket) do
    {:noreply, assign(socket, messages: messages, is_loading: is_loading)}
  end

  # --- LLM Integration using OpenRouter (streaming) ---

  defp stream_llm(history, system_prompt, lv_pid) do
    api_key = System.get_env("OPENROUTER_KEY")
    model = System.get_env("OPENROUTER_MODEL", "openai/gpt-4o-mini")

    if is_nil(api_key) or api_key == "" do
      send(lv_pid, {:stream_error, "Error: OPENROUTER_KEY not set in environment."})
      send(lv_pid, :stream_done)
    else
      messages = build_openrouter_messages(history, system_prompt)

      body = %{
        model: model,
        messages: messages,
        stream: true,
        temperature: 0.4
      }

      try do
        resp =
          Req.post!("https://openrouter.ai/api/v1/chat/completions",
            headers: [
              {"Authorization", "Bearer #{api_key}"},
              {"HTTP-Referer", "http://localhost:3000"},
              {"X-Title", "Personal Agent"}
            ],
            json: body,
            into: :self,
            receive_timeout: 300_000
          )

        # Consume using the recommended receive + parse_message loop for SSE
        consume = fn consume ->
          case Req.parse_message(resp, receive do m -> m end) do
            {:ok, [{:data, data}]} ->
              send_stream_tokens(data, lv_pid)
              consume.(consume)
            {:ok, [:done]} ->
              send(lv_pid, :stream_done)
            {:ok, _other} ->
              consume.(consume)
            {:error, reason} ->
              send(lv_pid, {:stream_error, "stream parse error: #{inspect(reason)}"})
          end
        end
        consume.(consume)
      rescue
        e ->
          send(lv_pid, {:stream_error, "LLM stream failed: #{Exception.message(e)}"})
          send(lv_pid, :stream_done)
      end
    end
  end

  defp send_stream_tokens(data, lv_pid) do
    data
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)

      cond do
        String.starts_with?(line, "data: [DONE]") ->
          send(lv_pid, :stream_done)

        String.starts_with?(line, "data: ") ->
          json_str = String.trim_leading(line, "data: ") |> String.trim()

          if json_str != "" and json_str != "[DONE]" do
            case Jason.decode(json_str) do
              {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
                if content = delta["content"] do
                  if is_binary(content) and content != "" do
                    send(lv_pid, {:stream_token, content})
                  end
                end

              {:ok, %{"error" => error}} ->
                send(lv_pid, {:stream_error, "LLM Error: #{inspect(error)}"})
                send(lv_pid, :stream_done)

              _ ->
                :ok
            end
          end

        true ->
          :ok
      end
    end)
  end

  defp build_openrouter_messages(history, system_prompt) do
    sys = [%{role: "system", content: system_prompt}]

    hist =
      Enum.map(history, fn msg ->
        %{role: msg.role, content: msg.content}
      end)

    sys ++ hist
  end

  # Render assistant content as nice Markdown (with basic sanitization fallback)
  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""
  defp render_markdown(content) when is_binary(content) do
    case Earmark.as_html(content, code_class_prefix: "language-") do
      {:ok, html, _messages} ->
        raw(html)
      _ ->
        # Fallback: escape plain text
        raw(Phoenix.HTML.html_escape(content))
    end
  end
end
