# AGENTS.md

Instructions for AI coding agents working in this repository.

## What this project is

Personal portfolio chat site: Phoenix LiveView frontend, Elixir backend, OpenRouter for LLM streaming. One LiveView (`ChatLive`) handles `/`, `/chat`, and `/c/:id`.

Despite the directory name, **all app code is Elixir** under `erlang_backend/`.

## Repository layout

| Path                                                     | Role                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------ |
| `erlang_backend/lib/agent_backend_web/live/chat_live.ex` | Chat UI, message handling, LLM streaming, URL routing        |
| `erlang_backend/lib/agent_backend/chat_sessions.ex`      | File-backed chat persistence (`priv/chat_sessions/*.json`)   |
| `erlang_backend/lib/agent_backend/system_prompt.ex`      | Loads `prompt.md` from repo root                             |
| `erlang_backend/assets/js/app.js`                        | LiveView client hooks; rebuild after edits                   |
| `erlang_backend/priv/chat_sessions/`                     | Runtime chat JSON files                                      |
| `erlang_backend/priv/static/`                            | Served static assets (built output)                          |
| `prompt.md`                                              | System prompt (gitignored, personal)                         |
| `.env`                                                   | Secrets (gitignored)                                         |

## Do not commit

These are in `.gitignore` and must stay local:

- `.env` — API keys, `SECRET_KEY_BASE`
- `prompt.md` — personal facts and tone rules / guardrails
- `erlang_backend/_build/`, `deps/`, `node_modules/`
- `erlang_backend/priv/chat_sessions/` — user chat data
- `erlang_backend/priv/static/assets/` — built JS/CSS
## Running locally

```bash
cd erlang_backend
mix deps.get && mix compile
mix phx.server
```

Server listens on **port 3000**. Requires `.env` at repo root and `prompt.md` for full functionality.

Production on this host uses `erlang_backend/scripts/server.sh`, which sources `../../.env`.

## Key architectural facts

### Chat persistence

`ChatLive` → `AgentBackend.ChatSessions` → JSON files in `priv/chat_sessions/<id>.json`

### LiveView URL sync

When a new chat starts from `/`, the server uses `push_patch(to: "/c/#{id}", replace: true)` — **not** client-only `history.replaceState`. This keeps LiveView's internal reconnect URL aligned with the browser URL. Do not revert to `replaceState`-only URL updates; it causes empty-home bugs after WebSocket reconnect.

`handle_params` has a guard: if `params["id"]` is nil but `assigns.chat_id` is set, keep in-memory messages (reconnect safety net).

### LLM streaming

- Browser ↔ server: LiveView WebSocket (`phx-submit="send_message"`)
- Server ↔ OpenRouter: HTTP SSE via `Req.post!` in a `Task.start` spawned from `do_send_message/2`
- Tokens arrive as `handle_info({:stream_token, ...})`; do not use `push_navigate` mid-stream (kills UX). `push_patch` is safe; `push_navigate` remounts.

### System prompt

Loaded from `prompt.md` at repo root (searched relative to cwd and `lib/`). Fallback: `SYSTEM_PROMPT` env var, then a short default string.

### WebSocket session

`endpoint.ex` passes `session: @session_options` to the LiveView socket `connect_info`. Keep session options in sync between `Plug.Session` and the socket.

## Making changes

### Elixir / LiveView

- Match existing style in `chat_live.ex` — minimal comments, focused diffs
- Use `push_patch` / `push_navigate` from Phoenix LiveView, not deprecated `live_patch`
- Verified routes (`~p"/..."`) require `use Phoenix.VerifiedRoutes` — this project often uses plain string paths instead

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

## Common pitfalls

| Mistake                                                            | Why it breaks                                            |
| ------------------------------------------------------------------ | -------------------------------------------------------- |
| Editing `priv/static/assets/app.js` directly                       | Overwritten on next asset build; edit `assets/js/app.js` |
| Running `docker compile` as root without fixing `_build` ownership | Leaves root-owned files; breaks local `mix compile`      |
| Using `push_navigate` for first-message URL update                 | Remounts LiveView and disrupts streaming                 |

## Testing changes

1. `mix compile` in `erlang_backend/`
2. Rebuild assets if JS/CSS changed
3. Restart server (`scripts/server.sh` or `mix phx.server`)
4. Verify: `curl http://localhost:3000/health`
5. Manual: start chat from `/`, confirm URL becomes `/c/:id`, reload shows messages, idle/reconnect does not wipe UI

## Deployment context

- Hosted on a home server, exposed via **Cloudflare Tunnel** to `scott.larkin.cc`
- No reverse-proxy config in this repo; tunnel handles TLS and routing
- WebSocket idle timeouts on proxies make correct LiveView URL sync important

## When unsure

Read before editing:

1. `erlang_backend/lib/agent_backend_web/live/chat_live.ex` — main behavior
2. `erlang_backend/lib/agent_backend/chat_sessions.ex` — persistence format
3. `erlang_backend/lib/agent_backend_web/endpoint.ex` — HTTP/WebSocket setup

Keep changes scoped. Do not refactor unrelated modules. Do not commit secrets or personal prompt content.

