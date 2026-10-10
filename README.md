# agent_peers

List and message live Claude Code and Codex sessions on this machine, from Ruby or the shell.

```ruby
require "agent_peers"

AgentPeers.list.each { |p| puts [p.kind, p.status, p.name, p.session_id].join(" ") }

# One-shot: registers this process for the send, listens `wait` seconds, deregisters.
r = AgentPeers.send_message("scrum master oct 8 2026", "status check, please", from_label: "canvas", wait: 10)
r[:delivery].status   # => :unconfirmed | :held | :denied | :expired | :dropped | :refused | :delivered
r[:messages]          # replies that arrived within the wait

# Long-lived (canvas server, worker): stays registered so replies can arrive any time.
session = AgentPeers::Session.new(name: "streamweaver-canvas").start
id = session.send_message("scrum master oct 8 2026", "status check?")
session.delivery(id).status                         # held? denied? or :unconfirmed
session.on_message { |m| puts "#{m.from_name}: #{m.text}" }
session.reply(msg, "thanks")                        # answers a received Message
session.notify_when_idle("scrum master oct 8 2026") # one :idle Message when it next goes idle
```

```bash
agent-peers list [--json]
agent-peers send REF "text" [--from LABEL] [--wait SECONDS]   # or pipe text on stdin
#   prints the delivery status; exit 2 when denied/expired/dropped/refused
```

`REF` is a full sessionId, a unique sessionId prefix (4+ chars), a pid, or an exact name. Names repeat
across sessions, so an ambiguous ref raises `AgentPeers::Ambiguous` instead of guessing.

## How it works

Claude Code writes one record per live session to `~/.claude/sessions/<pid>.json` (override with
`CLAUDE_CONFIG_DIR`) and listens on a Unix socket named in the record's `messagingSocketPath`. Codex
tasks join the same registry when the [claude-uds-bridge](https://github.com/LeonKohli/claude-uds-bridge)
plugin is installed and trusted (`entrypoint: "codex-claude-uds-bridge"`, reported as `kind: :codex`).
Sending is one newline-terminated JSON `user` frame written to that socket. No auth is needed for a
same-user write.

## Delivery status

Ordinary acceptance sends no receipt, so `:unconfirmed` means "bytes written, nothing said against
it", never "delivered". A receiver in a different permission mode HOLDS the message for its user
(`:held`), then it ends `:delivered`, `:denied` or `:expired`. The Codex bridge compares modes: a
`bypass` Codex task holds messages from a sender that declares none. See the Codex notes below.

## Caveats
- The wire format is a Claude Code internal with no compatibility promise. `Sender#build` is the only
  place that knows it, and `spec/sender_spec.rb` pins the shape. Verified on Claude Code 2.1.296.
- A successful send means the bytes reached the socket, not that the session read them. Ordinary
  acceptance sends no receipt. A session in a stricter permission mode may hold the message for its user.
- **Senders must be registered.** The Codex bridge silently drops any frame whose `from` is not a live, registered peer's socket (Claude sessions do not check). `send_message` therefore registers this process (a `sessions/<pid>.json` row plus a private socket in `/tmp/cc-socks`) for the duration of the send, then removes both. Replies and delivery receipts arrive on that socket: pass `wait: SECONDS` (`--wait`) to collect them. A process that wants replies after the call returns should hold a `Registration` open.
- Codex tasks in `prompting` mode accept messages from this gem directly. `bypass`-mode tasks (approval `never` plus full access, common on the desktop app) hold them, and the approval dialog may not render there. The gem never declares a `from-mode`, because faking one defeats the guard.
- A Codex task is invisible until its first turn runs (the plugin registers on `SessionStart`).
- Liveness is `kill -0` on the pid plus a socket file check. A reused pid could in theory pass.
- The calling session is hidden from `list` when `CLAUDE_CODE_SESSION_ID` is set (`exclude_self: false` to keep it).

## Tests

`bundle exec rspec`. Specs build a throwaway config dir and real Unix sockets; they never touch live sessions.
