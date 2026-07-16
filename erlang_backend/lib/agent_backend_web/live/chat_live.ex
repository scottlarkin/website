defmodule AgentBackendWeb.ChatLive do
  use AgentBackendWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]

  @user_error "Something went wrong on my side. Please try again."
  @user_error_hint "If it keeps happening, try a new chat."

  @suggestions [
    %{label: "Skills", prompt: "What are your technical skills?"},
    %{label: "Education", prompt: "Tell me about your education"},
    %{label: "Projects", prompt: "What projects have you worked on?"},
    %{label: "Experience", prompt: "What is your experience?"},
    %{label: "Contact", prompt: "How can I contact you?"}
  ]

  # Load .env if present (for OPENROUTER_KEY and SYSTEM_PROMPT)
  defp load_env do
    if Application.get_env(:agent_backend, :skip_dotenv, false) do
      :ok
    else
      do_load_env()
    end
  end

  defp do_load_env do
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

      quoted_envs =
        Regex.scan(~r/([A-Za-z0-9_]+)\s*=\s*"([\s\S]*?)"/, content, capture: :all_but_first)
        |> Enum.into(%{}, fn [k, v] -> {k, String.trim(v)} end)

      simple_matches =
        Regex.scan(~r/^([A-Za-z0-9_]+)\s*=\s*(?:"([^"]*)"|([^"\n]*))$/m, content, capture: :all_but_first)

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

    chat_id = normalize_chat_id(params["id"])
    live = if chat_id, do: AgentBackend.AgentRuns.live_state(chat_id), else: nil

    {messages, is_loading, agent_status, held_draft, run_id, thinking} =
      case live do
        %{messages: msgs, run_id: rid, agent_status: st, held_draft: held} ->
          {msgs, true, st || :generating, held, rid,
           AgentBackendWeb.TypingLines.random_line()}

        _ ->
          msgs = load_chat_messages(chat_id)
          {msgs, false, nil, nil, nil, nil}
      end

    socket =
      socket
      |> assign(
        messages: messages,
        input: "",
        is_loading: is_loading,
        agent_status: agent_status,
        held_draft: held_draft,
        validation_badge: false,
        thinking_line: thinking,
        chat_id: chat_id,
        run_id: run_id,
        suggestions: @suggestions,
        typewriter_prompts: Enum.map(@suggestions, & &1.prompt),
        input_placeholder: input_placeholder()
      )
      |> AgentBackendWeb.SEO.assigns(chat_id)
      |> subscribe_chat(chat_id)
      |> maybe_schedule_thinking()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    old_chat_id = socket.assigns[:chat_id]
    chat_id = normalize_chat_id(params["id"])

    live = if chat_id, do: AgentBackend.AgentRuns.live_state(chat_id), else: nil

    {messages, is_loading, agent_status, held_draft, run_id} =
      cond do
        is_nil(chat_id) and is_binary(old_chat_id) ->
          {socket.assigns.messages, socket.assigns.is_loading, socket.assigns.agent_status,
           socket.assigns.held_draft, socket.assigns.run_id}

        is_nil(chat_id) ->
          {[], false, nil, nil, nil}

        match?(%{messages: _}, live) ->
          %{messages: msgs, run_id: rid, agent_status: st, held_draft: held} = live
          {msgs, true, st || :generating, held, rid}

        chat_id == old_chat_id and socket.assigns.messages != [] and socket.assigns.is_loading ->
          {socket.assigns.messages, true, socket.assigns.agent_status, socket.assigns.held_draft,
           socket.assigns.run_id}

        true ->
          {load_chat_messages(chat_id), false, nil, nil, nil}
      end

    socket =
      socket
      |> unsubscribe_chat(old_chat_id)
      |> subscribe_chat(chat_id)
      |> assign(
        chat_id: chat_id,
        messages: messages,
        is_loading: is_loading,
        agent_status: agent_status,
        held_draft: held_draft,
        run_id: run_id,
        thinking_line:
          if(is_loading,
            do: socket.assigns[:thinking_line] || AgentBackendWeb.TypingLines.random_line(),
            else: nil
          )
      )
      |> AgentBackendWeb.SEO.assigns(chat_id)
      |> maybe_schedule_thinking()

    {:noreply, socket}
  end

  defp normalize_chat_id(id) when is_binary(id) do
    if AgentBackend.ChatSessions.valid_id?(id), do: id, else: nil
  end

  defp normalize_chat_id(_), do: nil

  defp load_chat_messages(nil), do: []

  defp load_chat_messages(chat_id) when is_binary(chat_id) do
    raw = AgentBackend.ChatSessions.get(chat_id) |> Map.get(:messages, [])
    # In-memory only while a run is active — never rewrite disk mid-stream.
    if AgentBackend.AgentRuns.active?(chat_id) do
      raw
    else
      drop_orphaned_assistant_placeholder(raw)
    end
  end

  defp drop_orphaned_assistant_placeholder(messages) do
    case List.last(messages) do
      %{role: "assistant", content: content, error: true} when content not in [nil, ""] ->
        messages

      %{role: "assistant", content: content} when content in [nil, ""] ->
        Enum.drop(messages, -1)

      _ ->
        messages
    end
  end

  defp load_sync_state(nil), do: {[], false, nil, nil, nil}

  defp load_sync_state(chat_id) when is_binary(chat_id) do
    case AgentBackend.AgentRuns.live_state(chat_id) do
      %{messages: msgs, run_id: rid, agent_status: st, held_draft: held} ->
        {msgs, true, rid, st || :generating, held}

      _ ->
        {load_chat_messages(chat_id), false, nil, nil, nil}
    end
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

  # Only used when starting a run — other tabs get stream_state from AgentRuns hub.
  defp broadcast_stream_state(chat_id, run_id, snapshot) when is_map(snapshot) do
    Phoenix.PubSub.broadcast(
      AgentBackend.PubSub,
      chat_topic(chat_id),
      {:agent_event, run_id, {:stream_state, snapshot}}
    )
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    {:noreply,
     socket
     |> assign(
       messages: [],
       input: "",
       chat_id: nil,
       run_id: nil,
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
    input =
      Map.get(params, "message") ||
        Map.get(params, "input") ||
        Map.get(params, "value") ||
        ""

    {:noreply, assign(socket, input: input)}
  end

  @impl true
  def handle_event("send_suggestion", %{"message" => message}, socket) do
    do_send_message(message, socket)
  end

  @impl true
  def handle_event("retry_last", _params, socket) do
    case last_assistant_index(socket.assigns.messages) do
      nil ->
        {:noreply, socket}

      idx ->
        handle_event("reload_message", %{"index" => Integer.to_string(idx)}, socket)
    end
  end

  @impl true
  def handle_event("reload_message", %{"index" => idx_param}, socket) do
    if socket.assigns.is_loading or busy?(socket) do
      {:noreply, socket}
    else
      case parse_nonneg_int(idx_param) do
        nil ->
          {:noreply, socket}

        idx ->
          messages = socket.assigns.messages
          last_idx = length(messages) - 1

          # Regenerating is only allowed on the most recent assistant turn so
          # mid-thread reload cannot wipe later messages (use branch instead).
          case Enum.at(messages, idx) do
            %{role: "assistant"} when idx == last_idx and last_idx >= 0 ->
              context = Enum.take(messages, idx)

              if last_user_content(context) do
                start_agent_for_messages(context, socket, log_user?: false)
              else
                {:noreply, socket}
              end

            _ ->
              {:noreply, socket}
          end
      end
    end
  end

  @impl true
  def handle_event("cancel_run", _params, socket) do
    chat_id = socket.assigns.chat_id
    run_id = socket.assigns.run_id

    if socket.assigns.is_loading and is_binary(chat_id) and is_binary(run_id) do
      case AgentBackend.AgentRuns.cancel(chat_id, run_id) do
        {:ok, messages} ->
          _ = AgentBackend.ChatSessions.save(chat_id, messages)

          broadcast_stream_state(chat_id, run_id, %{
            run_id: run_id,
            messages: messages,
            agent_status: nil,
            held_draft: nil,
            is_loading: false
          })

          {:noreply,
           assign(socket,
             messages: messages,
             is_loading: false,
             agent_status: nil,
             held_draft: nil,
             thinking_line: nil,
             validation_badge: false,
             run_id: nil
           )}

        :ignore ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sync_state", _params, socket) do
    require Logger
    Logger.info("chat sync_state chat_id=#{inspect(socket.assigns.chat_id)}")

    {messages, is_loading, run_id, agent_status, held_draft} =
      load_sync_state(socket.assigns.chat_id)

    socket =
      assign(socket,
        messages: messages,
        is_loading: is_loading,
        agent_status: agent_status,
        held_draft: held_draft,
        run_id: run_id,
        input: "",
        thinking_line:
          if(is_loading,
            do: socket.assigns.thinking_line || AgentBackendWeb.TypingLines.random_line(),
            else: nil
          )
      )
      |> maybe_schedule_thinking()

    {:noreply, socket}
  end

  defp busy?(socket) do
    case socket.assigns.chat_id do
      id when is_binary(id) -> AgentBackend.AgentRuns.active?(id)
      _ -> false
    end
  end

  defp do_send_message(raw_message, socket) do
    message = String.trim(raw_message)

    if message == "" or socket.assigns.is_loading or busy?(socket) do
      {:noreply, socket}
    else
      user_msg = %{
        role: "user",
        content: message,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      user_messages = socket.assigns.messages ++ [user_msg]
      start_agent_for_messages(user_messages, socket, log_user?: true)
    end
  end

  # messages must end with the last user turn (no assistant placeholder yet).
  defp start_agent_for_messages(user_messages, socket, opts) do
    log_user? = Keyword.get(opts, :log_user?, true)

    last_user =
      user_messages
      |> Enum.reverse()
      |> Enum.find(fn
        %{role: "user", content: c} when is_binary(c) and c != "" -> true
        _ -> false
      end)

    message = if last_user, do: last_user.content, else: ""

    if message == "" or socket.assigns.is_loading or busy?(socket) do
      {:noreply, socket}
    else
      assistant = %{
        role: "assistant",
        content: "",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      ui_messages = user_messages ++ [assistant]
      old_chat_id = socket.assigns[:chat_id]
      chat_id = old_chat_id || AgentBackend.ChatSessions.generate_id()
      run_id = Integer.to_string(System.unique_integer([:positive]))

      case AgentBackend.AgentRuns.try_start(chat_id, run_id, ui_messages) do
        {:error, :busy} ->
          {:noreply, socket}

        :ok ->
          AgentBackend.ChatSessions.save(chat_id, ui_messages)

          if log_user? do
            AgentBackend.SlackMonitor.log_user_message(chat_id, message)
          end

          # Push initial state so other open tabs join the stream immediately.
          broadcast_stream_state(chat_id, run_id, %{
            run_id: run_id,
            messages: ui_messages,
            agent_status: :generating,
            held_draft: nil,
            is_loading: true
          })

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
              chat_id: chat_id,
              run_id: run_id
            )
            |> schedule_thinking_tick()

          socket =
            if is_nil(old_chat_id) do
              Phoenix.LiveView.push_patch(socket, to: "/c/#{chat_id}", replace: true)
            else
              socket
            end

          Task.start(fn ->
            # Register before work so cancel can kill this runner process.
            # If cancel already cleared the hub, skip the LLM call entirely.
            case AgentBackend.AgentRuns.set_runner(chat_id, run_id, self()) do
              :ignore ->
                :ok

              :ok ->
                system_prompt = AgentBackend.SystemPrompt.load()
                require Logger
                Logger.info("Starting agent loop for: #{inspect(message)} (id=#{chat_id} run=#{run_id})")

                callbacks = agent_callbacks(chat_id, run_id)

                task =
                  Task.async(fn ->
                    AgentBackend.AgentLoop.run(user_messages, system_prompt, callbacks)
                  end)

                try do
                  case Task.yield(task, agent_timeout_ms()) || Task.shutdown(task, :brutal_kill) do
                    {:ok, content} when is_binary(content) and content != "" ->
                      # Only persist if we still own the run (not cancelled).
                      case AgentBackend.AgentRuns.finish(chat_id, run_id) do
                        :ok ->
                          persist_assistant_reply(chat_id, user_messages, content)
                          broadcast_agent_event(chat_id, run_id, :stream_done_finalize)

                        :already_done ->
                          :ok
                      end

                    {:ok, _} ->
                      _ = AgentBackend.AgentRuns.finish(chat_id, run_id)
                      :ok

                    nil ->
                      Logger.warning("Agent loop timed out for chat #{chat_id}")

                      case apply_and_broadcast_error(chat_id, run_id, :timeout) do
                        :ok ->
                          AgentBackend.SlackMonitor.log_error(chat_id, :timeout, "Response timed out")
                          persist_error_assistant(chat_id, user_messages)

                        :ignore ->
                          :ok
                      end

                      _ = AgentBackend.AgentRuns.finish(chat_id, run_id)

                    {:exit, reason} ->
                      Logger.warning("Agent loop crashed for chat #{chat_id}: #{inspect(reason)}")

                      case apply_and_broadcast_error(chat_id, run_id, :crash) do
                        :ok ->
                          AgentBackend.SlackMonitor.log_error(chat_id, :crash, inspect(reason))
                          persist_error_assistant(chat_id, user_messages)

                        :ignore ->
                          :ok
                      end

                      _ = AgentBackend.AgentRuns.finish(chat_id, run_id)
                  end
                after
                  _ = AgentBackend.AgentRuns.finish(chat_id, run_id)
                end
            end
          end)

          {:noreply, socket}
      end
    end
  end

  defp last_user_content(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: "user", content: c} when is_binary(c) and c != "" -> c
      _ -> nil
    end)
  end

  defp last_assistant_index(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {%{role: "assistant"}, idx} -> idx
      _ -> nil
    end)
  end

  defp parse_nonneg_int(val) when is_integer(val) and val >= 0, do: val

  defp parse_nonneg_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_nonneg_int(_), do: nil

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
  def handle_info({:agent_event, run_id, event}, socket) do
    # Accept stream_state even if we just opened (run_id may still be nil).
    if run_matches?(socket, run_id) or match?({:stream_state, _}, event) do
      handle_agent_event(event, socket, run_id)
    else
      {:noreply, socket}
    end
  end

  defp run_matches?(socket, run_id) do
    case socket.assigns[:run_id] do
      nil -> true
      ^run_id -> true
      _ -> false
    end
  end

  # Absolute multi-tab snapshot — never rebroadcast (hub is source of truth).
  defp handle_agent_event({:stream_state, snap}, socket, run_id) when is_map(snap) do
    socket =
      socket
      |> assign(
        messages: Map.get(snap, :messages, socket.assigns.messages),
        is_loading: Map.get(snap, :is_loading, true),
        agent_status: Map.get(snap, :agent_status),
        held_draft: Map.get(snap, :held_draft),
        run_id: run_id,
        thinking_line:
          if(empty_assistant_placeholder?(Map.get(snap, :messages, [])),
            do: socket.assigns.thinking_line || AgentBackendWeb.TypingLines.random_line(),
            else: nil
          )
      )
      |> maybe_schedule_thinking()

    {:noreply, socket}
  end

  defp handle_agent_event(:stream_done, socket, _run_id),
    do: handle_agent_event({:stream_done, %{}}, socket, nil)

  defp handle_agent_event({:stream_done, meta}, socket, _run_id) when is_map(meta) do
    # Keep current streamed text; clear loading. Finalize may reload from disk shortly.
    socket =
      assign(socket,
        is_loading: false,
        agent_status: nil,
        held_draft: nil,
        thinking_line: nil,
        validation_badge: Map.get(meta, :validated, false)
      )

    {:noreply, socket}
  end

  defp handle_agent_event(:stream_done_finalize, socket, _run_id) do
    # After Task persists, pull disk so late joiners get the full answer.
    messages =
      case socket.assigns.chat_id do
        id when is_binary(id) ->
          AgentBackend.ChatSessions.get(id)
          |> Map.get(:messages, socket.assigns.messages)

        _ ->
          socket.assigns.messages
      end

    {:noreply,
     assign(socket,
       messages: messages,
       is_loading: false,
       agent_status: nil,
       held_draft: nil,
       thinking_line: nil
     )}
  end

  defp handle_agent_event({:stream_error, _reason}, socket, _run_id) do
    # Error content already applied via stream_state from hub when possible;
    # fall back to local generic error UI.
    error_msg = user_facing_error_message()
    now = now_iso()

    messages =
      case List.last(socket.assigns.messages) do
        %{role: "assistant"} = last ->
          updated =
            last
            |> Map.put(:content, error_msg)
            |> Map.put(:error, true)
            |> Map.put(:timestamp, now)

          List.replace_at(socket.assigns.messages, length(socket.assigns.messages) - 1, updated)

        _ ->
          socket.assigns.messages ++
            [%{role: "assistant", content: error_msg, timestamp: now, error: true}]
      end

    {:noreply,
     assign(socket,
       messages: messages,
       is_loading: false,
       agent_status: nil,
       held_draft: nil,
       thinking_line: nil,
       validation_badge: false
     )}
  end

  defp handle_agent_event(_other, socket, _run_id), do: {:noreply, socket}

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp normalize_msg(msg, default_ts) when is_map(msg) do
    %{
      role: to_string(Map.get(msg, :role) || Map.get(msg, "role") || "user"),
      content: to_string(Map.get(msg, :content) || Map.get(msg, "content") || ""),
      timestamp: to_string(Map.get(msg, :timestamp) || Map.get(msg, "timestamp") || default_ts)
    }
  end

  defp agent_callbacks(chat_id, run_id) do
    hub_broadcast = fn
      {:ok, snapshot} -> broadcast_stream_state(chat_id, run_id, snapshot)
      :ignore -> :ok
    end

    %{
      on_token: fn token ->
        hub_broadcast.(AgentBackend.AgentRuns.append_token(chat_id, run_id, token))
      end,
      on_reset: fn ->
        hub_broadcast.(AgentBackend.AgentRuns.reset_assistant(chat_id, run_id))
      end,
      on_hold_draft: fn ->
        hub_broadcast.(AgentBackend.AgentRuns.hold_draft(chat_id, run_id))
      end,
      on_status: fn status ->
        hub_broadcast.(AgentBackend.AgentRuns.set_status(chat_id, run_id, status))
      end,
      on_done: fn meta ->
        broadcast_agent_event(chat_id, run_id, {:stream_done, meta})
      end,
      on_error: fn msg ->
        AgentBackend.SlackMonitor.log_error(chat_id, :stream_error, to_string(msg))
        apply_and_broadcast_error(chat_id, run_id, :stream_error)
      end
    }
  end

  # Returns `:ok` if this run still owned the hub, `:ignore` if already cancelled/finished.
  defp apply_and_broadcast_error(chat_id, run_id, _kind) do
    error_msg = user_facing_error_message()

    case AgentBackend.AgentRuns.set_error(chat_id, run_id, error_msg) do
      {:ok, snapshot} ->
        broadcast_stream_state(chat_id, run_id, Map.put(snapshot, :is_loading, false))
        broadcast_agent_event(chat_id, run_id, {:stream_error, :stream_error})
        :ok

      :ignore ->
        :ignore
    end
  end

  defp broadcast_agent_event(chat_id, run_id, event)
       when is_binary(chat_id) and is_binary(run_id) do
    Phoenix.PubSub.broadcast(
      AgentBackend.PubSub,
      chat_topic(chat_id),
      {:agent_event, run_id, event}
    )
  end

  defp persist_assistant_reply(chat_id, user_messages, content)
       when is_binary(chat_id) and is_binary(content) do
    now = now_iso()

    base = Enum.map(user_messages, &normalize_msg(&1, now))

    messages =
      base ++
        [
          %{
            role: "assistant",
            content: content,
            timestamp: now
          }
        ]

    case AgentBackend.ChatSessions.save(chat_id, messages) do
      :ok ->
        AgentBackend.SlackMonitor.log_assistant_message(chat_id, content)

      other ->
        require Logger
        Logger.warning("persist_assistant_reply save failed for #{chat_id}: #{inspect(other)}")
    end
  end

  defp persist_error_assistant(chat_id, user_messages) when is_binary(chat_id) do
    now = now_iso()
    error_msg = user_facing_error_message()

    base = Enum.map(user_messages, &normalize_msg(&1, now))

    messages =
      base ++
        [
          %{
            role: "assistant",
            content: error_msg,
            timestamp: now,
            error: true
          }
        ]

    _ = AgentBackend.ChatSessions.save(chat_id, messages)
  end

  defp schedule_thinking_tick(socket) do
    Process.send_after(self(), :thinking_tick, 2000)
    socket
  end

  defp maybe_schedule_thinking(socket) do
    if thinking_active?(socket), do: schedule_thinking_tick(socket), else: socket
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

  def user_facing_error_message, do: @user_error
  def user_facing_error_hint, do: @user_error_hint

  def message_error?(%{error: true}), do: true
  def message_error?(%{"error" => true}), do: true
  def message_error?(%{"error" => "true"}), do: true
  def message_error?(_), do: false

  def message_has_content?(%{content: c}) when is_binary(c) and c != "", do: true
  def message_has_content?(%{"content" => c}) when is_binary(c) and c != "", do: true
  def message_has_content?(_), do: false

  def agent_status_label(nil), do: nil
  def agent_status_label(:generating), do: nil
  def agent_status_label(:revising), do: "Tightening that up…"
  def agent_status_label(label) when is_binary(label), do: label
  def agent_status_label(_), do: nil

  def format_timestamp(""), do: nil
  def format_timestamp(nil), do: nil

  def format_timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%d %b, %H:%M UTC")
      _ -> nil
    end
  end

  defp input_placeholder do
    hour = Time.utc_now().hour

    cond do
      hour < 5 -> "Still curious? Ask away…"
      hour < 12 -> "Ask about the stack…"
      hour < 18 -> "Curious about a project?"
      true -> "How to get in touch?"
    end
  end

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(content) when is_binary(content) do
    case Earmark.as_html(content, code_class_prefix: "language-") do
      {:ok, html, _messages} ->
        raw(sanitize_html(html))

      _ ->
        escaped =
          content
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.Safe.to_iodata()
          |> IO.iodata_to_binary()

        raw(escaped)
    end
  end

  # Light XSS mitigation without a new dependency.
  def sanitize_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<\s*script\b[^>]*>.*?<\s*\/\s*script\s*>/is, "")
    |> String.replace(~r/<\s*iframe\b[^>]*>.*?<\s*\/\s*iframe\s*>/is, "")
    |> String.replace(~r/<\s*object\b[^>]*>.*?<\s*\/\s*object\s*>/is, "")
    |> String.replace(~r/<\s*embed\b[^>]*\/?>/is, "")
    |> String.replace(~r/\son\w+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/i, "")
    |> String.replace(~r/javascript\s*:/i, "")
  end
end
