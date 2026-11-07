require "open3"

module PeerPressure
  # What the herdr transports (Hc, Herdr) share: running a CLI and delivering one line through it.
  # Neither gives a delivery receipt, so callers treat a send as :unconfirmed.
  module CliTransport
    ERROR_PREVIEW = 80 # characters of CLI output kept in an Undeliverable message
    TIMEOUT = 5        # seconds before a hung CLI is killed; list and send must never hang
    BLOCKED = "blocked" # agent status while waiting at an approval or question dialog

    # A callable that runs `bin ARGS` and returns [output, success?]; a missing binary or a
    # timeout counts as failure. Injectable so specs never touch live terminals.
    def self.runner(bin, timeout: TIMEOUT)
      lambda do |*args|
        Open3.popen2e(bin, *args) do |stdin, out, wait|
          stdin.close
          if wait.join(timeout)
            [out.read, wait.value.success?]
          else
            Process.kill("KILL", wait.pid)
            ["", false]
          end
        end
      rescue SystemCallError
        ["", false]
      end
    end

    # Subclasses supply #command (the CLI args that deliver `line` to `peer`) and #default_runner.
    class Sender
      def initialize(from_label: "peerpressure", runner: nil)
        @from_label = from_label
        @runner = runner || default_runner
      end

      # Returns the peer's address (there is no message id to return). Refuses an agent that is
      # blocked at an approval dialog: pasting text and pressing Enter there could pick "Yes".
      def deliver(peer, text)
        raise ArgumentError, "empty message" if text.to_s.strip.empty?
        raise Undeliverable, "#{peer.name} is blocked at a dialog; answer it yourself" if peer.status == BLOCKED
        args = command(peer, "[from #{@from_label}] #{text}")
        out, ok = @runner.call(*args)
        raise Undeliverable, "#{args.first(2).join(' ')} failed: #{out.strip[0, ERROR_PREVIEW]}" unless ok
        peer.session_id
      end
    end
  end
end
