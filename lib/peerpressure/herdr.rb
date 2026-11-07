require "json"

module PeerPressure
  # Reaches agents in PLAIN herdr (the terminal multiplexer, `herdr`), as opposed to the desktop
  # app's herdr-core (see Hc). `herdr agent list` is the roster and `herdr agent prompt NAME TEXT`
  # is the delivery; it refuses an agent waiting at an approval dialog (agent_blocked) before
  # sending any input, which is the behaviour we want. Like Hc, there is no receipt.
  #
  # UNVERIFIED: no plain-herdr server was running when this was written, so the JSON shape of
  # `herdr agent list` is assumed to be {"result": {"agents": [{name, agent, status, cwd}]}}, the
  # `.result` envelope herdr's other commands use. If it differs, Registry#peers returns [] and
  # plain-herdr agents silently do not appear; check against a live server and fix `agents_in`.
  module Herdr
    Runner = CliTransport.runner(ENV.fetch("PEERPRESSURE_HERDR_BIN", "herdr"))

    class Registry
      def initialize(runner: Runner) = @runner = runner

      def peers
        out, ok = @runner.call("agent", "list")
        return [] unless ok
        agents_in(JSON.parse(out)).filter_map { |a| to_peer(a) }
      rescue JSON::ParserError
        []
      end

      # ref: the agent's live name (herdr's own address for an agent).
      def find(ref)
        hits = peers.select { |p| p.name == ref.to_s }
        raise NotFound, "no plain-herdr agent named #{ref.inspect}" if hits.empty?
        raise Ambiguous, "#{ref.inspect} matches #{hits.size} agents" if hits.size > 1
        hits.first
      end

      private

      def agents_in(json) = json.is_a?(Hash) ? Array(json.dig("result", "agents")) : []

      def to_peer(agent)
        return unless agent.is_a?(Hash) && agent["name"]
        Peer.new(session_id: agent["name"], name: agent["name"], kind: (agent["agent"] || "agent").tr("-", "_").to_sym,
                 cwd: agent["cwd"], status: agent["status"], entrypoint: "herdr")
      end
    end

    class Sender < CliTransport::Sender
      private

      def default_runner = Runner
      def command(peer, line) = ["agent", "prompt", peer.session_id, line]
    end
  end
end
