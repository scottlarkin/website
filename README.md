# Scott — Personal AI Chat Site

A personal portfolio chat site built with **Elixir**, **Phoenix LiveView**, and **OpenRouter**. Visitors chat with an AI that speaks as you, grounded in a local system prompt.

Live at [scott.larkin.cc](https://scott.larkin.cc)

## Features

- Real-time streaming chat over Phoenix LiveView WebSockets
- Shareable chat URLs (`/c/:id`) with JSON file persistence
- System prompt loaded from `prompt.md` at the repo root
- LLM integration with server-side SSE streaming
- Dark, minimal chat UI (Tailwind CSS)

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

This sources `.env` from the repo root and auto-restarts `mix phx.server` on crash. A systemd unit template lives at `erlang_backend/scripts/agent-backend.service`.

## Docker

```bash
docker compose up --build
```

Runs on port **3000**. Mounts `erlang_backend/` and expects `OPENROUTER_KEY` and `SYSTEM_PROMPT` from `.env`.

## Configuration

| Variable           | Purpose                                        |
| ------------------ | ---------------------------------------------- |
| `OPENROUTER_KEY`   | API key for LLM requests                       |
| `OPENROUTER_MODEL` | Model slug (default in `.env.example`)         |
| `SECRET_KEY_BASE`  | Phoenix session signing (`mix phx.gen.secret`) |
| `LIVE_VIEW_SALT`   | LiveView session signing (`mix phx.gen.secret`) |
| `PHX_HOST`         | Public hostname for URL generation             |
| `SYSTEM_PROMPT`    | Fallback prompt if `prompt.md` is missing      |

**System prompt:** `prompt.md` at the repo root is the primary source. It is gitignored because it contains personal facts and tone instructions. See `AgentBackend.SystemPrompt` for load order.

## Project layout

```
website/
├── .env.example          # Environment template (committed)
├── prompt.md             # Your AI system prompt (local only, gitignored)
├── docker-compose.yml
└── erlang_backend/       # Elixir/Phoenix app (despite the directory name)
    ├── lib/
    │   ├── agent_backend/          # Domain logic
    │   │   ├── chat_sessions.ex    # JSON file chat persistence
    │   │   └── system_prompt.ex    # Loads prompt.md
    │   └── agent_backend_web/      # Phoenix web layer
    │       ├── live/chat_live.ex   # Main chat UI + LLM streaming
    │       └── router.ex
    ├── assets/                     # JS/CSS source (esbuild + Tailwind)
    ├── priv/
    │   ├── chat_sessions/          # Persisted chats (*.json, gitignored)
    │   └── static/                 # Built assets served to browsers
    ├── config/
    └── scripts/
        ├── server.sh               # Auto-restart wrapper
        └── agent-backend.service   # systemd unit template
```

> **Note:** The app directory is named `erlang_backend` because Elixir runs on the BEAM (Erlang VM). All application code is Elixir.

## How chat works

1. User submits a message in `ChatLive` via LiveView WebSocket.
2. Messages are saved immediately to `priv/chat_sessions/<id>.json`.
3. On the first message, the URL patches to `/c/:id` via `push_patch` (no full page reload).
4. A background `Task` streams tokens from OpenRouter; partial responses are saved as they arrive.
5. Assistant replies are rendered as Markdown (Earmark).

## Health check

`GET /health` — returns 200 when the server is up.

## Customization

- **AI personality and facts:** edit `prompt.md`
- **UI:** `erlang_backend/lib/agent_backend_web/live/chat_live.html.heex`, `assets/css/app.css`
- **Client hooks:** `erlang_backend/assets/js/app.js`

## Building assets

From `erlang_backend/`:

```bash
mix assets.build    # Tailwind CSS + esbuild JS
mix assets.deploy   # above + phx.digest (use for production)
```

Built files land in `erlang_backend/priv/static/` (gitignored).

