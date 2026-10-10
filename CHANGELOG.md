# Changelog

## 0.2.0

- Canvas relay: `peer canvas-relay CANVAS` forwards StreamWeaver form submits to a pinned session as messages, re-pushes a delivery-status page with the answer kept and a Resend button, reconnects when the bridge restarts, and is idempotent per canvas.
- `peer demo`: pushes a demo form pinned to the calling session and starts its relay.
- `PeerPressure::Target`: pins a session by id and by process (pid plus start time), so a pinned form survives `/clear`. `Registry#resolve`, `Peer#proc_start`.

## 0.1.0

First release.

- `PeerPressure.list` / `find`: every live Claude Code and Codex session, from the session registry.
- `PeerPressure.send_message`: one-shot send that registers the calling process for the duration, with a `Delivery` status (`:unconfirmed`, `:held`, `:denied`, `:expired`, `:dropped`, `:refused`, `:delivered`).
- `PeerPressure::Session`: long-lived peer with `on_message`, `inbox`, `wait_for`, `reply`, `notify_when_idle`.
- `peer list` / `peer send` CLI (exit code 2 when a message is denied, expired, dropped or refused).
- Codex tasks via the claude-uds-bridge plugin.
- Verified on macOS with Claude Code 2.1.296. The wire format is unofficial and may change.
