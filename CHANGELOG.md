# Changelog

## 0.1.0

First release.

- `PeerPressure.list` / `find`: every live Claude Code and Codex session, from the session registry.
- `PeerPressure.send_message`: one-shot send that registers the calling process for the duration, with a `Delivery` status (`:unconfirmed`, `:held`, `:denied`, `:expired`, `:dropped`, `:refused`, `:delivered`).
- `PeerPressure::Session`: long-lived peer with `on_message`, `inbox`, `wait_for`, `reply`, `notify_when_idle`.
- `peer list` / `peer send` CLI (exit code 2 when a message is denied, expired, dropped or refused).
- Codex tasks via the claude-uds-bridge plugin.
- Verified on macOS with Claude Code 2.1.296. The wire format is unofficial and may change.
