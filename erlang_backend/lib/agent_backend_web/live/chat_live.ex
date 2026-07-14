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
        agent_status: nil,
        held_draft: nil,
        validation_badge: false,
        thinking_line: nil,
        chat_id: chat_id,
        suggestions: [
          "What are your technical skills?",
          "Tell me about your education",
          "What projects have you worked on?",
          "What is your experience?",
          "How can I contact you?"
        ]
      )
      |> AgentBackendWeb.SEO.assigns(chat_id)
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
      |> AgentBackendWeb.SEO.assigns(chat_id)

    {:noreply, socket}
  end

  defp load_chat_messages(nil), do: []

  defp load_chat_messages(chat_id) when is_binary(chat_id) do
    raw = AgentBackend.ChatSessions.get(chat_id) |> Map.get(:messages, [])
    cleaned = drop_orphaned_assistant_placeholder(raw)

    if cleaned != raw do
      AgentBackend.ChatSessions.save(chat_id, cleaned)
    end

    cleaned
  end

  defp drop_orphaned_assistant_placeholder(messages) do
    case List.last(messages) do
      %{role: "assistant", content: content} when content in [nil, ""] ->
        Enum.drop(messages, -1)

      _ ->
        messages
    end
  end

  defp load_sync_state(nil), do: {[], false}

  defp load_sync_state(chat_id) when is_binary(chat_id) do
    {load_chat_messages(chat_id), false}
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

  defp broadcast_chat_sync(socket, messages, is_loading, agent_status \\ :skip, held_draft \\ :skip) do
    agent_status = if agent_status == :skip, do: socket.assigns[:agent_status], else: agent_status
    held_draft = if held_draft == :skip, do: socket.assigns[:held_draft], else: held_draft

    if chat_id = socket.assigns.chat_id do
      Phoenix.PubSub.broadcast_from(
        AgentBackend.PubSub,
        self(),
        chat_topic(chat_id),
        {:chat_sync,
         %{
           messages: messages,
           is_loading: is_loading,
           agent_status: agent_status,
           held_draft: held_draft
         }}
      )
    end

    socket
  end

  @impl true
  def handle_event("new_chat", _params, socket), do: new_chat(socket)

  defp new_chat(socket) do
    {:noreply,
     socket
     |> assign(
       messages: [],
       input: "",
       chat_id: nil,
       is_loading: false,
       agent_status: nil,
       held_draft: nil,
       validation_badge: false,
       thinking_line: nil
     )
     |> Phoenix.LiveView.push_navigate(to: "/")}
  end

  @impl true
  def handle_event("dismiss_validation_badge", _params, socket) do
    {:noreply, assign(socket, validation_badge: false)}
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

  @impl true
  def handle_event("sync_state", _params, socket) do
    require Logger
    Logger.info("chat sync_state chat_id=#{inspect(socket.assigns.chat_id)}")

    {messages, is_loading} = load_sync_state(socket.assigns.chat_id)

    {:noreply,
     assign(socket, messages: messages, is_loading: is_loading, agent_status: nil, held_draft: nil, input: "")}
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
      AgentBackend.SlackMonitor.log_user_message(chat_id, message)

      # Update local state
      socket =
        socket
        |> unsubscribe_chat(old_chat_id)
        |> subscribe_chat(chat_id)
        |> assign(
          messages: ui_messages,
          is_loading: true,
          agent_status: :generating,
          held_draft: nil,
          validation_badge: false,
          thinking_line: AgentBackendWeb.TypingLines.random_line(),
          input: "",
          chat_id: chat_id
        )
        |> schedule_thinking_tick()
        |> broadcast_chat_sync(ui_messages, true, :generating)

      # First message: sync URL to /c/:id without remounting (push_patch, not push_navigate).
      socket =
        if is_nil(old_chat_id) do
          Phoenix.LiveView.push_patch(socket, to: "/c/#{chat_id}", replace: true)
        else
          socket
        end

      Task.start(fn ->
        system_prompt = AgentBackend.SystemPrompt.load()
        require Logger
        Logger.info("Starting agent loop for: #{inspect(message)} (id=#{chat_id})")

        callbacks = agent_callbacks(chat_id)

        task =
          Task.async(fn ->
            AgentBackend.AgentLoop.run(user_messages, system_prompt, callbacks)
          end)

        case Task.yield(task, agent_timeout_ms()) || Task.shutdown(task, :brutal_kill) do
          {:ok, content} when is_binary(content) and content != "" ->
            persist_assistant_reply(chat_id, content)

          {:ok, _} ->
            :ok

          nil ->
            Logger.warning("Agent loop timed out for chat #{chat_id}")
            broadcast_agent_event(chat_id, {:stream_error, "Response timed out. Please try again."})
            AgentBackend.SlackMonitor.log_error(chat_id, :timeout, "Response timed out. Please try again.")

          {:exit, reason} ->
            Logger.warning("Agent loop crashed for chat #{chat_id}: #{inspect(reason)}")
            broadcast_agent_event(chat_id, {:stream_error, "Something went wrong. Please try again."})
            AgentBackend.SlackMonitor.log_error(chat_id, :crash, inspect(reason))
        end
      end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:thinking_tick, socket) do
    if thinking_active?(socket) do
      line = AgentBackendWeb.TypingLines.random_line(socket.assigns.thinking_line)

      {:noreply,
       socket
       |> assign(thinking_line: line)
       |> schedule_thinking_tick()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_event, event}, socket), do: handle_agent_event(event, socket)

  @impl true
  def handle_info({:stream_token, token}, socket), do: handle_agent_event({:stream_token, token}, socket)

  defp handle_agent_event({:stream_token, token}, socket) do
    {socket, messages} = maybe_start_revision_stream(socket)

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
          |> broadcast_chat_sync(messages, true, :skip, :skip)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:hold_draft, socket), do: handle_agent_event(:hold_draft, socket)

  defp handle_agent_event(:hold_draft, socket) do
    held_draft =
      case List.last(socket.assigns.messages) do
        %{role: "assistant", content: content} when is_binary(content) and content != "" -> content
        _ -> nil
      end

    socket =
      socket
      |> assign(held_draft: held_draft, agent_status: :revising)
      |> broadcast_chat_sync(socket.assigns.messages, true, :revising, held_draft)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:stream_reset, socket), do: handle_agent_event(:stream_reset, socket)

  defp handle_agent_event(:stream_reset, socket) do
    messages = socket.assigns.messages

    if messages != [] do
      last_idx = length(messages) - 1
      last = List.last(messages)

      if last && last.role == "assistant" do
        updated = %{last | content: ""}
        messages = List.replace_at(messages, last_idx, updated)

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
  def handle_info({:agent_status, status}, socket), do: handle_agent_event({:agent_status, status}, socket)

  defp handle_agent_event({:agent_status, status}, socket) do
    socket =
      socket
      |> assign(agent_status: status)
      |> broadcast_chat_sync(socket.assigns.messages, true, status, :skip)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:stream_done, socket), do: handle_agent_event(:stream_done, socket)

  defp handle_agent_event(:stream_done, socket), do: handle_agent_event({:stream_done, %{}}, socket)

  defp handle_agent_event({:stream_done, meta}, socket) when is_map(meta) do
    # Ensure the final state is saved
    if chat_id = socket.assigns.chat_id do
      AgentBackend.ChatSessions.save(chat_id, socket.assigns.messages)
    end

    socket =
      socket
      |> assign(
        is_loading: false,
        agent_status: nil,
        held_draft: nil,
        thinking_line: nil,
        validation_badge: Map.get(meta, :validated, false)
      )
      |> broadcast_chat_sync(socket.assigns.messages, false, nil, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_error, error_msg}, socket), do: handle_agent_event({:stream_error, error_msg}, socket)

  defp handle_agent_event({:stream_error, error_msg}, socket) do
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
          |> assign(
            messages: messages,
            is_loading: false,
            agent_status: nil,
            held_draft: nil,
            thinking_line: nil
          )
          |> broadcast_chat_sync(messages, false, nil, nil)

        {:noreply, socket}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:chat_sync, %{messages: messages, is_loading: is_loading} = payload}, socket) do
    {:noreply,
     assign(socket,
       messages: messages,
       is_loading: is_loading,
       agent_status: Map.get(payload, :agent_status),
       held_draft: Map.get(payload, :held_draft)
     )}
  end

  defp maybe_start_revision_stream(socket) do
    if socket.assigns[:held_draft] do
      messages = clear_last_assistant_content(socket.assigns.messages)

      socket =
        socket
        |> assign(messages: messages, held_draft: nil)
        |> broadcast_chat_sync(messages, true, :skip, nil)

      {socket, messages}
    else
      {socket, socket.assigns.messages}
    end
  end

  defp clear_last_assistant_content([]), do: []

  defp clear_last_assistant_content(messages) do
    last_idx = length(messages) - 1
    last = List.last(messages)

    if last && last.role == "assistant" do
      List.replace_at(messages, last_idx, %{last | content: ""})
    else
      messages
    end
  end

  defp agent_callbacks(chat_id) do
    %{
      on_token: fn token -> broadcast_agent_event(chat_id, {:stream_token, token}) end,
      on_reset: fn -> broadcast_agent_event(chat_id, :stream_reset) end,
      on_hold_draft: fn -> broadcast_agent_event(chat_id, :hold_draft) end,
      on_status: fn status -> broadcast_agent_event(chat_id, {:agent_status, status}) end,
      on_done: fn meta -> broadcast_agent_event(chat_id, {:stream_done, meta}) end,
      on_error: fn msg ->
        broadcast_agent_event(chat_id, {:stream_error, msg})
        AgentBackend.SlackMonitor.log_error(chat_id, :stream_error, msg)
      end
    }
  end

  defp broadcast_agent_event(chat_id, event) when is_binary(chat_id) do
    Phoenix.PubSub.broadcast(AgentBackend.PubSub, chat_topic(chat_id), {:agent_event, event})
  end

  defp persist_assistant_reply(chat_id, content) when is_binary(chat_id) and is_binary(content) do
    messages = AgentBackend.ChatSessions.get(chat_id) |> Map.get(:messages, [])
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    messages =
      case List.last(messages) do
        %{role: "assistant"} = last ->
          List.replace_at(messages, length(messages) - 1, %{last | content: content, timestamp: now})

        _ ->
          messages ++ [%{role: "assistant", content: content, timestamp: now}]
      end

    AgentBackend.ChatSessions.save(chat_id, messages)
    AgentBackend.SlackMonitor.log_assistant_message(chat_id, content)
  end

  defp schedule_thinking_tick(socket) do
    Process.send_after(self(), :thinking_tick, 2000)
    socket
  end

  defp thinking_active?(socket) do
    socket.assigns.is_loading and empty_assistant_placeholder?(socket.assigns.messages)
  end

  defp empty_assistant_placeholder?(messages) do
    case List.last(messages) do
      %{role: "assistant", content: ""} -> true
      %{"role" => "assistant", "content" => ""} -> true
      _ -> false
    end
  end

  defp agent_timeout_ms do
    case Integer.parse(System.get_env("AGENT_TIMEOUT_MS", "180000")) do
      {n, _} when n > 0 -> n
      _ -> 180_000
    end
  end

  def agent_status_label(nil), do: nil
  def agent_status_label(:generating), do: nil
  def agent_status_label(:revising), do: "Improving accuracy…"
  def agent_status_label(label) when is_binary(label), do: label
  def agent_status_label(_), do: nil

  def format_timestamp(""), do: nil
  def format_timestamp(nil), do: nil

  def format_timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%d %b, %H:%M UTC")

      _ ->
        nil
    end
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
