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

## Gotchas

- Wire format is internal to Claude Code; if sends stop arriving after an upgrade, fix `Sender#build` and the spec together.
- Replies go to the registered socket, which exists only while a Registration is open; a one-shot CLI call deregisters (after `wait`), so a Codex reply approved later has nowhere to land.
- Never test against live sessions in specs: use `spec/spec_helper.rb`'s `FakeFleet` (real `UNIXServer` in a tmpdir).
- A sent message may be held for the user's approval by a stricter-mode receiver; Codex asks before replying.
- The Codex plugin decides hold vs accept by permission MODE (`app-server.ts permissionMode`): approval `never` + `dangerFullAccess` = bypass; else prompting. A prompting receiver accepts a sender with no declared mode; a bypass receiver holds it. Never fake `from-mode`.
- `notify_when_idle` is verified live against Claude Code; the idle notice's `detail` is the session's own one-line status.
- Do not print `CLAUDE_CODE_MESSAGING_TOKEN`; this gem does not need it.
