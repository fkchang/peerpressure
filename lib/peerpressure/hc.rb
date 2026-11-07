require "json"

module PeerPressure
  # Reaches agents that run in herdr-core terminals (Copilot, Gemini, anything without a Claude
  # Code inbox socket). `herdr-core ls` is the roster and `herdr-core send` is the delivery:
  # it pastes the text and presses enter. There is no receipt, so a send is always :unconfirmed.
  module Hc
    Runner = CliTransport.runner(ENV.fetch("PEERPRESSURE_HC_BIN", "herdr-core"))

    class Registry
      def initialize(runner: Runner) = @runner = runner

      # Live AGENT terminals as Peers; kind is the agent name herdr reports (:copilot, :codex, ...).
      # A terminal with no detected agent (a shell) is skipped: sending to it would run the text as
      # shell commands. socket_path is nil: delivery goes through hc.
      def peers
        out, ok = @runner.call("ls", "--json")
        return [] unless ok
        json = JSON.parse(out)
        return [] unless json.is_a?(Hash)
        Array(json["terminals"]).select { |t| t["state"] == "live" && t["agent"] }.map { |t| to_peer(t) }
      rescue JSON::ParserError
        []
      end

      # ref: terminal address (t4) or exact name.
      def find(ref)
        ref = ref.to_s
        hits = peers.select { |p| p.session_id == ref || p.name == ref }
        raise NotFound, "no live herdr terminal matches #{ref.inspect}" if hits.empty?
        raise Ambiguous, "#{ref.inspect} matches #{hits.size} terminals" if hits.size > 1
        hits.first
      end

      private

      def to_peer(term)
        Peer.new(session_id: term["address"], name: term["name"] || term["address"],
                 kind: term["agent"].tr("-", "_").to_sym, cwd: term["cwd"],
                 status: term["status"], entrypoint: "herdr-core")
      end
    end

    class Sender < CliTransport::Sender
      private

      def default_runner = Runner
      def command(peer, line) = ["send", peer.session_id, line]
    end
  end
end
