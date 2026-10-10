require "json"
require "securerandom"
require "socket"

module PeerPressure
  # Writes one "user" frame to a session's inbox socket. Ordinary acceptance sends no
  # receipt, so a successful return means the bytes reached the socket, not that the
  # session read them: a session in a stricter permission mode may hold the message
  # for its user.
  class Sender
    MAX_LINE = 1_048_576 # characters per frame, per the bridge's protocol notes
    SETTLE = 0.3 # the macOS receiver can lose the last frame if the sender closes or deregisters at once

    def initialize(from_label: "peerpressure", priority: "next", from: nil)
      @from_label = from_label
      @priority = priority
      @from = from
    end

    # Returns the msg_id.
    def deliver(peer, text)
      frame = build(peer, text)
      line = JSON.generate(frame)
      raise Undeliverable, "message too long (#{line.length} > #{MAX_LINE})" if line.length > MAX_LINE
      write(peer.socket_path, line + "\n")
      frame[:msg_id]
    end

    # Asks the peer for ONE peer_idle_notice when it next goes idle (or exits). Costs it nothing.
    # The notice arrives as a Message(kind: :idle).
    def subscribe_idle(peer)
      frame = { type: "control", msgV: 1, action: "notify_when_idle", msg_id: SecureRandom.uuid,
                from: @from || "uds:/tmp/cc-socks/#{@from_label}-#{Process.pid}.sock", session_id: peer.session_id }
      write(peer.socket_path, JSON.generate(frame) + "\n")
      frame[:msg_id]
    end

    def build(peer, text)
      raise ArgumentError, "empty message" if text.to_s.strip.empty?
      {
        type: "user", msgV: 1, msg_id: SecureRandom.uuid,
        from: @from || "uds:/tmp/cc-socks/#{@from_label}-#{Process.pid}.sock",
        session_id: peer.session_id, priority: @priority,
        message: { role: "user", content: "[from #{@from_label}] #{text}" }
      }
    end

    private

    def write(path, data)
      UNIXSocket.open(path) { |sock| sock.write(data); sleep 0.15 }
    rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EACCES => e
      raise Undeliverable, "#{e.class.name.split('::').last} on #{path}"
    end
  end
end
