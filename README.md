# Scott — Personal AI Chat Site

A personal portfolio chat site built with **Elixir**, **Phoenix LiveView**, and **OpenRouter**. Visitors chat with an AI that speaks as you, grounded in a local system prompt (`prompt.md`).

Live at [scott.larkin.cc](https://scott.larkin.cc)

## Features

- Real-time streaming chat over Phoenix LiveView WebSockets
- **Agent loop** — stream a draft, LLM-backed fact check, optional revise, then finalize
- Shareable chat URLs (`/c/:id`) with atomic JSON file persistence
- Single-flight runs (one agent Task per chat) with multi-tab stream sync via PubSub
- **Stop** mid-response (keeps partial text if any streamed)
- **Reload** last assistant reply only (same prior context)
- **Branch** any message into a new chat tab (`/branch/:chat_id/:index` → new `/c/:id`)
- System prompt loaded from `prompt.md` at the repo root
- Optional Slack monitoring — one thread per chat, separate error channel
- Dark, minimal chat UI (Tailwind CSS) with revision UX (held draft, status labels)

## Requirements

- Elixir ~> 1.17
- Erlang/OTP 27+
- Node.js (for Tailwind/esbuild asset pipeline)
- An [OpenRouter](https://openrouter.ai/) API key

## Quick start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env — set OPENROUTER_KEY, SECRET_KEY_BASE, etc.

# 2. Create your system prompt (not committed to git)
# Add prompt.md at the repo root with your facts and tone instructions.

# 3. Install and run
cd erlang_backend
mix deps.get
mix esbuild.install --if-missing
mix compile
mix phx.server
```

Visit [http://localhost:3000](http://localhost:3000).

### Production-style local run

```bash
./erlang_backend/scripts/server.sh
```

Sources `.env` from the repo root, runs `mix assets.deploy`, then starts `mix phx.server` (auto-restarts on crash). A systemd unit template lives at `erlang_backend/scripts/agent-backend.service`.

### Dev server (port 3001)

Leaves a production instance on 3000 untouched:

```bash
./erlang_backend/scripts/dev-server.sh
# DEV_PORT=3002 ./erlang_backend/scripts/dev-server.sh
# ./erlang_backend/scripts/dev-server.sh --build   # rebuild assets first
```

## Docker

```bash
docker compose up --build
```

Runs on port **3000**. Mounts `erlang_backend/` and expects `OPENROUTER_KEY` and related vars from `.env`.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `OPENROUTER_KEY` | — | API key for LLM requests |
| `OPENROUTER_MODEL` | `nvidia/nemotron-3-ultra-550b-a55b:free` | Main chat model |
| `OPENROUTER_VALIDATOR_MODEL` | same as main | Validator-only model override |
| `SECRET_KEY_BASE` | — | Phoenix session signing (`mix phx.gen.secret`) |
| `LIVE_VIEW_SALT` | — | LiveView signing salt (`mix phx.gen.secret`) |
| `PHX_HOST` | — | Public hostname for URL generation |
| `PORT` | `3000` | HTTP listen port (`runtime.exs`; dev-server defaults to `3001`) |
| `SYSTEM_PROMPT` | short fallback | Used only if `prompt.md` is missing |
| `AGENT_MAX_ITERS` | `5` | Max agent loop iterations |
| `AGENT_MAX_VALIDATION_RETRIES` | `2` | Max validation-driven revisions |
| `AGENT_TIMEOUT_MS` | `180000` | Background agent Task timeout |
| `SLACK_BOT_TOKEN` | — | Slack bot token (`chat:write`; optional) |
| `SLACK_MONITOR_CHANNEL_ID` | — | Channel for per-chat threads (optional) |
| `SLACK_ERRORS_CHANNEL_ID` | — | Channel for error alerts (optional) |

**System prompt:** `prompt.md` at the repo root is the primary source (gitignored). Load order is handled by `AgentBackend.SystemPrompt` (`prompt.md` → `SYSTEM_PROMPT` → short default).

Slack monitoring is enabled only when **all three** Slack vars are set; otherwise it no-ops.

## Architecture

```
Browser  ──LiveView WS──►  ChatLive
                              │
                              ├─ AgentRuns (single-flight + live hub + cancel)
                              ├─ ChatSessions (serialized JSON persistence)
                              ├─ PubSub chat:<id> (tokens, status, multi-tab sync)
                              │
                              └─ Task ──► AgentLoop
                                            ├─ OpenRouter stream (SSE) / complete
                                            └─ Tools.OutputValidator (LLM fact check)

Browser  ──GET /branch/:chat_id/:index──►  BranchController ──► new /c/:id
```

### Components

| Module | Role |
| --- | --- |
| `ChatLive` | UI, send/stop/reload, URL routing (`/`, `/chat`, `/c/:id`), spawns agent Task |
| `BranchController` | Fork transcript at message index into a new shareable chat |
| `AgentLoop` | Stream draft → auto-validate → revise → finalize |
| `AgentRuns` | At most one run per `chat_id`; live messages/status; cancelable runner PID |
| `ChatSessions` | File-backed sessions under `priv/chat_sessions/<id>.json` |
| `OpenRouter` | Streaming (SSE) and non-streaming chat completions |
| `Tools` / `OutputValidator` | Extensible tool registry; pure-LLM grounding checker |
| `SlackMonitor` | One monitor-channel thread per chat; errors channel for failures |
| `SystemPrompt` | Loads `prompt.md` |

Supervised children (`AgentBackend.Application`): PubSub, ChatSessions, AgentRuns, SlackMonitor, Endpoint.

### Agent loop

On each user message, `ChatLive` starts a background Task that runs `AgentBackend.AgentLoop.run/3`:

1. **Stream draft** — OpenRouter SSE without tools in the request (some free models do not stream reliably with tools). Falls back to non-streaming `complete/2` if the stream is empty or errors.
2. **Validate** — `output_validator` is invoked by the loop (`auto_validate`), not via model `tool_calls`. UI shows “Checking accuracy…”.
3. **Revise** (if validation fails and retries remain) — holds a dimmed draft (`held_draft`), streams a corrected reply with issue feedback. UI shows “Tightening that up…”.
4. **Done** — loading clears; optional “Double-checked against my notes” badge when validation passed.

Validation is **pure LLM** (no deterministic string-matching rules). The validator returns compact JSON (`{"passed": true}` or `{"passed": false, "issues": [...]}`). Unparseable responses and validator API errors **default to pass** (lenient) to avoid revision spam.

### Persistence

`ChatSessions` serializes all writes through a GenServer. Writes are atomic (`*.tmp` + rename).

- Chat ids match `^[A-Za-z0-9]{6,12}$`.
- On send, the Task path saves the user turn + empty assistant placeholder immediately.
- **The agent Task owns final disk state** (`persist_assistant_reply` / `persist_error_assistant`). LiveViews do **not** rewrite full history on every token or on `stream_done`.
- Empty overwrite of a non-empty transcript is refused (`{:error, :refuse_empty}`).
- Trailing empty assistant placeholders are dropped **in memory only** when loading (while a run is active, disk is not rewritten mid-stream).
- Session JSON may also store `slack_thread_ts` (preserved across saves).

### Streaming & multi-tab

- Browser ↔ server: LiveView WebSocket (`phx-submit="send_message"`).
- Server ↔ OpenRouter: HTTP SSE in the background Task.
- Agent callbacks update `AgentRuns` and broadcast on `chat:<id>` as `{:agent_event, run_id, event}` — not direct messages only to the originating LiveView pid. Any subscribed tab receives tokens, status, done, and errors; `run_id` filters stale runs.
- First message from `/` uses `push_patch(to: "/c/:id", replace: true)` so LiveView’s reconnect URL matches the browser (do not use client-only `history.replaceState` for this).
- Only the **last** assistant message renders raw text while generating; earlier messages stay Markdown (Earmark).

### Slack monitoring (optional)

Set `SLACK_BOT_TOKEN`, `SLACK_MONITOR_CHANNEL_ID`, and `SLACK_ERRORS_CHANNEL_ID`. The bot needs `chat:write` and must be invited to both channels.

- **Monitor channel** — first activity posts a parent (`Chat <id> — <url>`); user messages and **finalized** assistant replies are thread replies (not streaming tokens or intermediate validation drafts).
- **Errors channel** — stream errors, task timeouts, and task crashes.

## Project layout

```
website/
├── .env.example                 # Environment template (committed)
├── prompt.md                    # AI system prompt (local only, gitignored)
├── AGENTS.md                    # Deeper agent/dev notes for this repo
├── docker-compose.yml
└── erlang_backend/              # Elixir/Phoenix app (all app code lives here)
    ├── lib/
    │   ├── agent_backend/
    │   │   ├── agent_loop.ex        # Stream → validate → revise
    │   │   ├── agent_runs.ex        # Single-flight + live stream hub
    │   │   ├── chat_sessions.ex     # JSON file persistence
    │   │   ├── open_router.ex       # LLM client (stream + complete)
    │   │   ├── tools.ex             # Tool registry
    │   │   ├── tools/output_validator.ex
    │   │   ├── slack.ex / slack_monitor.ex
    │   │   └── system_prompt.ex
    │   └── agent_backend_web/
    │       ├── live/chat_live.ex    # UI + Task orchestration
    │       ├── live/chat_live.html.heex
    │       └── router.ex
    ├── assets/                      # JS/CSS source (esbuild + Tailwind)
    ├── test/                        # ExUnit + LLM/Slack fakes
    ├── priv/
    │   ├── chat_sessions/           # Persisted chats (*.json, gitignored)
    │   └── static/                  # Built assets (served)
    ├── config/
    └── scripts/
        ├── server.sh                # Prod-style run + assets.deploy
        ├── dev-server.sh            # Port 3001 (or DEV_PORT)
        └── agent-backend.service    # systemd unit template
```

> **Note:** The app directory is named `erlang_backend` because Elixir runs on the BEAM (Erlang VM). All application code is Elixir.

## Health check

`GET /health` — returns 200 when the server is up.

## Testing

Tests do not call OpenRouter or Slack; they use fakes configured in `config/test.exs` (`:llm`, `:slack`).

```bash
cd erlang_backend
mix compile
mix test
```

Coverage includes the agent loop (validate/revise), AgentRuns single-flight, ChatSessions refuse-empty, multi-tab stream sync, SlackMonitor, and LiveView send/error paths.

## Customization

- **AI personality and facts:** edit `prompt.md`
- **UI:** `erlang_backend/lib/agent_backend_web/live/chat_live.html.heex`, `assets/css/app.css`
- **Client hooks:** `erlang_backend/assets/js/app.js` (`AutoScroll`, `RevisionCrossfade`, `ChatForm`, typewriter, copy link)
- **New tools:** implement `AgentBackend.Tools.Behaviour`, register in `AgentBackend.Tools`

## Building assets

From `erlang_backend/`:

```bash
mix assets.build    # Tailwind CSS + esbuild JS
mix assets.deploy   # above + phx.digest (use for production)
```

Edit source under `erlang_backend/assets/`, not `priv/static/` (generated). `scripts/server.sh` runs `mix assets.deploy` before starting the server.
