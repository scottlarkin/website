# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this project is

Personal portfolio chat site: Phoenix LiveView frontend, Elixir backend, OpenRouter for LLM streaming. One LiveView (`ChatLive`) handles `/`, `/chat`, and `/c/:id`.

Despite the directory name, **all app code is Elixir** under `erlang_backend/`.

The chat uses an **agent loop**: stream a draft reply, run an LLM-backed `output_validator`, optionally revise, then finalize. Validation is **pure LLM** (no deterministic string-matching checks).

## Repository layout

| Path                                                            | Role                                                                   |
| --------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `erlang_backend/lib/agent_backend_web/live/chat_live.ex`        | Chat UI, agent task spawn, PubSub stream events, URL routing           |
| `erlang_backend/lib/agent_backend_web/live/chat_live.html.heex` | Message rendering, held-draft revision UX                              |
| `erlang_backend/lib/agent_backend/agent_loop.ex`                | Stream → validate → revise loop                                        |
| `erlang_backend/lib/agent_backend/open_router.ex`               | OpenRouter streaming + non-streaming client                            |
| `erlang_backend/lib/agent_backend/tools.ex`                     | Extensible tool registry                                               |
| `erlang_backend/lib/agent_backend/tools/output_validator.ex`    | LLM fact-checker tool                                                  |
| `erlang_backend/lib/agent_backend/chat_sessions.ex`             | Serialized file-backed chat persistence (`priv/chat_sessions/*.json`)  |
| `erlang_backend/lib/agent_backend/agent_runs.ex`                | Single-flight agent run registry (one run per chat)                    |
| `erlang_backend/lib/agent_backend/slack.ex`                     | Slack Web API client (`chat.postMessage`)                              |
| `erlang_backend/lib/agent_backend/slack_monitor.ex`             | Async GenServer: one Slack thread per chat, error alerts               |
| `erlang_backend/lib/agent_backend/system_prompt.ex`             | Loads `prompt.md` from repo root                                       |
| `erlang_backend/assets/js/app.js`                               | LiveView client hooks (`RevisionCrossfade`, etc.); rebuild after edits |
| `erlang_backend/priv/chat_sessions/`                            | Runtime chat JSON files                                                |
| `erlang_backend/priv/static/`                                   | Served static assets (built output)                                    |
| `erlang_backend/priv/static/images/favicon.svg`                 | Favicon source (served under `/images/…` after digest)                 |
| `prompt.md`                                                     | System prompt (gitignored, personal)                                   |
| `.env`                                                          | Secrets (gitignored)                                                   |

## Do not commit

These are in `.gitignore` and must stay local:

- `.env` — API keys, `SECRET_KEY_BASE`, `SLACK_BOT_TOKEN`
- `prompt.md` — personal facts and tone rules / guardrails
- `erlang_backend/_build/`, `deps/`, `node_modules/`
- `erlang_backend/priv/chat_sessions/` — user chat data
- `erlang_backend/priv/static/assets/` — built JS/CSS

## Running locally

```bash
# systemd user service (auto-restart, runs assets.deploy on start)
systemctl --user restart agent-backend.service

# Or manually:
./erlang_backend/scripts/server.sh
```

`server.sh` sources `../../.env` and runs `mix assets.deploy` before `mix phx.server`.

**Dev/test server** (port **3001**, leaves prod untouched):

```bash
./erlang_backend/scripts/dev-server.sh
# DEV_PORT=3002 ./scripts/dev-server.sh  # alternate port
# ./scripts/dev-server.sh --build        # rebuild assets first
```

**One-off compile + run** (defaults to port 3000):

```bash
cd erlang_backend
mix deps.get && mix compile
mix phx.server
```

Requires `.env` at repo root and `prompt.md` for full functionality.

## Key architectural facts

### Chat persistence

`ChatLive` → `AgentBackend.ChatSessions` (GenServer) → JSON files in `priv/chat_sessions/<id>.json`

- Writes are serialized and atomic (`*.tmp` + rename)
- **Task owns final disk state** (`persist_assistant_reply` / `persist_error_assistant`). LiveViews must **not** save full history on `stream_done` / per-token
- Empty overwrite of a non-empty transcript is **refused** (`{:error, :refuse_empty}`)
- Chat ids must match `^[A-Za-z0-9]{6,12}$`
- On load/sync, trailing empty assistant placeholders are dropped **in memory only** while a run is active (never rewrite disk mid-stream)

Session JSON may also include `slack_thread_ts` — preserved across `save/2` under the same lock.

### Agent single-flight

`AgentBackend.AgentRuns` allows at most one agent Task per `chat_id`. New sends while busy are no-ops. PubSub events are tagged with `run_id`; LiveViews ignore stale runs.

### Slack monitoring

Optional async monitoring via `AgentBackend.SlackMonitor` (supervised GenServer).

- **Monitor channel** — first message in a chat posts a parent (`Chat <id> — <url>`), then all user and finalized agent replies go in that thread
- **Errors channel** — agent `stream_error`, task timeout, and task crash (logged at source in `agent_callbacks` / `do_send_message` Task, not in LiveView handlers)

Env vars (all required when enabled; missing any → no-op):

| Variable                     | Purpose                          |
| ---------------------------- | -------------------------------- |
| `SLACK_BOT_TOKEN`            | Bot token with `chat:write`      |
| `SLACK_MONITOR_CHANNEL_ID`   | Channel for chat threads         |
| `SLACK_ERRORS_CHANNEL_ID`    | Channel for error alerts         |

Hook points in `chat_live.ex`: `do_send_message` (user), `persist_assistant_reply` (agent), `on_error` callback + Task timeout/crash. Do not post streaming tokens or validation intermediate drafts.

### Agent loop

`ChatLive.do_send_message/2` spawns a background task that runs `AgentBackend.AgentLoop.run/3`.

Flow per user message:

1. **Stream draft** — OpenRouter SSE without tools in the request (Nemotron free does not stream reliably with tools). Falls back to non-streaming `complete/2` if the stream is empty.
2. **Validate** — `output_validator` runs via `auto_validate/6` (not model tool_calls). Shows "Checking accuracy…" in the UI.
3. **Revise** (if validation fails and retries remain) — holds dimmed draft (`held_draft`), streams a corrected reply with validation feedback. Shows "Improving accuracy…".
4. **Done** — `on_done` clears loading state.

Env tuning (all optional):

| Variable                       | Default                                  | Purpose                         |
| ------------------------------ | ---------------------------------------- | ------------------------------- |
| `OPENROUTER_MODEL`             | `nvidia/nemotron-3-ultra-550b-a55b:free` | Main chat model                 |
| `OPENROUTER_VALIDATOR_MODEL`   | same as main                             | Validator-only model override   |
| `AGENT_MAX_ITERS`              | `5`                                      | Max agent loop iterations       |
| `AGENT_MAX_VALIDATION_RETRIES` | `2`                                      | Max validation-driven revisions |
| `AGENT_TIMEOUT_MS`             | `180000`                                 | Background task timeout         |

Validator returns compact JSON (`{"passed": true}` or `{"passed": false, "issues": [...]}`). Unparseable validator responses and API errors **default to pass** (lenient) to avoid revision spam.

The task also **persists the final assistant reply to disk** when the loop completes, so reloads/reconnects still get the answer even if the originating LiveView died.

### Stream events (PubSub)

Agent callbacks broadcast to `chat:<id>` as `{:agent_event, event}` — not direct `send` to the LiveView pid. Any subscribed `ChatLive` for that chat receives tokens, status, done, and errors. This survives WebSocket reconnect and page reload.

`broadcast_chat_sync/4` separately syncs multi-tab UI state via `{:chat_sync, ...}`.

### LiveView URL sync

When a new chat starts from `/`, the server uses `push_patch(to: "/c/#{id}", replace: true)` — **not** client-only `history.replaceState`. This keeps LiveView's internal reconnect URL aligned with the browser URL. Do not revert to `replaceState`-only URL updates; it causes empty-home bugs after WebSocket reconnect.

`handle_params` has a guard: if `params["id"]` is nil but `assigns.chat_id` is set, keep in-memory messages (reconnect safety net).

### LLM streaming

- Browser ↔ server: LiveView WebSocket (`phx-submit="send_message"`)
- Server ↔ OpenRouter: HTTP SSE via `Req.post` in a `Task` spawned from `do_send_message/2`
- Tokens arrive as `handle_info({:agent_event, {:stream_token, token}})`; do not use `push_navigate` mid-stream (kills UX). `push_patch` is safe; `push_navigate` remounts.
- Only the **last** assistant message renders raw text during `:generating`; earlier messages stay Markdown.

### Revision UX

- `held_draft` — dimmed previous draft while revising
- `RevisionCrossfade` JS hook — crossfade when revision stream starts
- Template shows Markdown when not actively generating the last message

### System prompt

Loaded from `prompt.md` at repo root (searched relative to cwd and `lib/`). Fallback: `SYSTEM_PROMPT` env var, then a short default string.

### WebSocket session

`endpoint.ex` passes `session: @session_options` to the LiveView socket `connect_info`. Keep session options in sync between `Plug.Session` and the socket.

### Static files

`Plug.Static` `only` list allows directory prefixes (`assets`, `images`, etc.). **Do not serve digested root-level files** like `favicon-<hash>.svg` — `only: ~w(favicon.svg)` won't match hashed names. Favicon lives at `priv/static/images/favicon.svg`; layout uses `static_path("/images/favicon.svg")`.

## Making changes

### Elixir / LiveView

- Match existing style in `chat_live.ex` — minimal comments, focused diffs
- Use `push_patch` / `push_navigate` from Phoenix LiveView, not deprecated `live_patch`
- Verified routes (`~p"/..."`) require `use Phoenix.VerifiedRoutes` — this project often uses plain string paths instead
- To add a tool: implement `AgentBackend.Tools.Behaviour`, register in `AgentBackend.Tools` `@tools` list

### Frontend

- Edit source in `erlang_backend/assets/`, not `priv/static/` (generated)
- Rebuild after JS/CSS changes:

```bash
cd erlang_backend
mix assets.build    # Tailwind CSS + esbuild JS
mix assets.deploy   # above + phx.digest (production)
```

`scripts/server.sh` runs `mix assets.deploy` before starting the server.

### Config

- App config: `erlang_backend/config/config.exs` (port 3000, esbuild paths)
- Env-specific: `dev.exs`, `prod.exs`, `runtime.exs`
- `PORT` env overrides listen port (`runtime.exs`); dev-server defaults to 3001

## Common pitfalls

| Mistake                                                            | Why it breaks                                                            |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| Editing `priv/static/assets/app.js` directly                       | Overwritten on next asset build; edit `assets/js/app.js`                 |
| Favicon at repo root of `priv/static/` with digest                 | Digested `favicon-<hash>.svg` 404s — use `images/favicon.svg`            |
| Sending stream events only to `self()` pid                         | Lost on reload/reconnect; use PubSub `broadcast_agent_event/2`           |
| `stream_in_progress?` on empty assistant placeholder               | Stuck "Thinking…" after orphaned streams                                 |
| Using `push_navigate` for first-message URL update                 | Remounts LiveView and disrupts streaming                                 |
| Running `docker compile` as root without fixing `_build` ownership | Leaves root-owned files; breaks local `mix compile`                      |
| Adding deterministic validation rules                              | User wants pure LLM validator; prompt changes must not fight code checks |

## Testing changes

**Always run tests (and compile) before starting or restarting any server.** Do not skip this to “save time.”

```bash
cd erlang_backend
mix compile
mix test
# If JS/CSS changed:
mix assets.build    # or assets.deploy for prod-style digest
```

Only after green tests:

1. Dev: `./scripts/dev-server.sh` (3001). Prod: `systemctl --user restart agent-backend.service` (3000)
2. Verify: `curl http://localhost:3001/health` (dev) or `:3000/health` (prod)
3. Manual: start chat from `/`, confirm URL becomes `/c/:id`, reload shows messages, idle/reconnect does not wipe UI
4. Agent: check logs for `AgentLoop validation passed/failed`, `OutputValidator completed in Xms`
5. Concurrent safety: second tab on same `/c/:id` mid-stream must not wipe history after done
6. Revision UX: validation fail should show held draft + revise status + crossfade
7. Slack (if configured): new chat creates monitor-channel thread; user + agent replies appear as thread messages; errors go to errors channel only

Regression tests live under `erlang_backend/test/` (ChatSessions refuse-empty, AgentRuns single-flight, sanitizer, tools).

## Deployment context

- Prod: `agent-backend.service` (user systemd) runs `scripts/server.sh` on port 3000
- No reverse-proxy config in this repo; tunnel handles TLS and routing
- WebSocket idle timeouts on proxies make correct LiveView URL sync important

## When unsure

Read before editing:

1. `erlang_backend/lib/agent_backend_web/live/chat_live.ex` — main behavior
2. `erlang_backend/lib/agent_backend/agent_loop.ex` — stream/validate/revise loop
3. `erlang_backend/lib/agent_backend/tools/output_validator.ex` — validator prompt
4. `erlang_backend/lib/agent_backend/chat_sessions.ex` — persistence format
5. `erlang_backend/lib/agent_backend/slack_monitor.ex` — Slack thread lifecycle
6. `erlang_backend/lib/agent_backend_web/endpoint.ex` — HTTP/WebSocket/static setup

Keep changes scoped. Do not refactor unrelated modules. Do not commit secrets or personal prompt content.

