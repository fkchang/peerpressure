# peerpressure for LLMs

Ruby gem + CLI (`exe/peer`) to discover and message live Claude Code and Codex sessions.

## API

| Call | Returns |
|---|---|
| `PeerPressure.list(config_dir:, exclude_self:)` | `Peer[]`, newest first (`session_id, name, kind(:claude/:codex), pid, cwd, status, started_at, socket_path`) |
| `PeerPressure.find(ref)` | one `Peer`; raises `NotFound` / `Ambiguous` |
| `PeerPressure.send_message(ref, text, from_label:, wait: 0)` | `{delivery: Delivery, messages: [Message]}`; `Delivery#status` is `:unconfirmed` (no receipt: NOT proof of delivery), `:held`, `:denied`, `:expired`, `:dropped`, `:refused`, `:delivered`; raises `Undeliverable` |
| `PeerPressure::Session.new(name:).start` | long-lived peer: `send_message`, `delivery(id)`, `on_message`, `inbox`, `wait_for(from_session:, timeout:)`, `reply(msg, text)`, `notify_when_idle(ref)`, `receipts_for(id)`, `stop` |

## Files

- `lib/peerpressure/registry.rb`: reads `<config>/sessions/*.json`, liveness = `kill -0` + socket file; `find` order is sessionId, pid, exact name, sessionId prefix.
- `lib/peerpressure/sender.rb`: the ONLY file that knows the wire format (`type:"user", msgV:1, msg_id, from, session_id, priority:"next", message:{role,content}`, newline-delimited JSON). Content is prefixed `[from LABEL]` because the socket shows no sender name.
- `lib/peerpressure/registration.rb`: registers THIS process (row + 0600 socket in a 0700 dir + accept loop into `#frames`). Required because the Codex receiver drops frames whose `from` isn't a live registered peer (`bridge.ts receive()`), silently. Hold one open for long-lived callers (canvas) so replies can arrive.
- `lib/peerpressure/session.rb`, `message.rb`, `delivery.rb`: long-lived wrapper, parsed inbound frames (message / receipt / idle, envelope unwrapped), and the status fold.
- `lib/peerpressure/peer.rb`: `kind` is `:codex` iff `entrypoint == "codex-claude-uds-bridge"`.

## Canvas relay (`require "peerpressure/canvas"`, needs the stream_weaver gem)

`peer canvas-relay CANVAS [--to REF] [--submit REGEX]` (idempotent, detached; `--foreground` to debug), `peer canvas-relay stop CANVAS | list`, `peer demo [CANVAS] [--to REF]`. Default target is the session the command runs inside (`CLAUDE_CODE_SESSION_ID`).

- Why a relay: the canvas bridge forwards click events only to connected clients and drops them otherwise, and canvas DSL is not run server-side with `submit` blocks. The relay is the standing listener (`Client.each_event`), so forms never time out.
- Files: `canvas/relay.rb` (event loop, forwarding, reconnect), `canvas/status_view.rb` (page after a submit; every dynamic string via `#inspect`, values HTML-escaped), `canvas/formatter.rb` (message text), `canvas/lifecycle.rb` (pidfile at `~/.peerpressure/relays/<canvas>.json`, `ensure_running`), `canvas/stream_weaver_client.rb` (the only file that touches StreamWeaver), `canvas/demo.rb`, `target.rb` (pin by session id AND pid + proc_start).
- The `action` event's `state` carries the whole form; the relay drops the Save-as-doc widget's `scope`/`name` keys.
- After pushing a form, the agent should END ITS TURN. Do not poll the canvas or block on `canvas-wait`.
- Specs: `spec/canvas/*` use a fake client and fake session plus real sockets in a tmpdir.

## reply_to sink (no relay process; needs a StreamWeaver with reply_to)

`streamweaver canvas-push NAME --reply-to "$(peer reply-to)"` (or `peer demo --via reply-to`). `peer reply-to [--to REF]` prints `peerpressure:<target JSON>`; the payload may also be a bare session id or name.

- `canvas/sink.rb` is the `canvas_event_sink` StreamWeaver's bridge calls (on its own thread per event). It keeps one `Relay` per (canvas, payload) behind a lock, so Resend keeps its last answer, and reuses `Relay#handle` and `StatusView`; `ContextClient` turns the relay's `push` into the bridge's `ctx.push`. One shared `Session` ("streamweaver-canvas") is created lazily for the whole bridge process.
- `stream_weaver.rb` is the loader advertised in the gemspec (`stream_weaver.extensions.v1`); the bridge discovers extensions ONLY at boot, so install the gem, then restart the bridge.
- The bridge's own env may carry `CLAUDE_CODE_SESSION_ID` of whichever agent started it, so the sink's registry is `exclude_self: false`.
- An unresolvable target is explained on the canvas (status page), not raised, and retried on the next press.
- Ordering is not guaranteed by StreamWeaver (thread per event); the sink serializes per canvas for itself.

## Gotchas

- Wire format is internal to Claude Code; if sends stop arriving after an upgrade, fix `Sender#build` and the spec together.
- Replies go to the registered socket, which exists only while a Registration is open; a one-shot CLI call deregisters (after `wait`), so a Codex reply approved later has nowhere to land.
- Never test against live sessions in specs: use `spec/spec_helper.rb`'s `FakeFleet` (real `UNIXServer` in a tmpdir).
- A sent message may be held for the user's approval by a stricter-mode receiver; Codex asks before replying.
- The Codex plugin decides hold vs accept by permission MODE (`app-server.ts permissionMode`): approval `never` + `dangerFullAccess` = bypass; else prompting. A prompting receiver accepts a sender with no declared mode; a bypass receiver holds it. Never fake `from-mode`.
- `notify_when_idle` is verified live against Claude Code; the idle notice's `detail` is the session's own one-line status.
- Do not print `CLAUDE_CODE_MESSAGING_TOKEN`; this gem does not need it.
