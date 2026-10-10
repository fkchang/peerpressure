require "json"
require "time"

module AgentPeers
  # Reads the session registry. A record counts as live when its pid still runs and
  # its socket file exists; a stale file can outlive its process.
  class Registry
    attr_reader :dir

    def initialize(config_dir: ENV["CLAUDE_CONFIG_DIR"] || File.expand_path("~/.claude"), exclude_self: true)
      @dir = File.join(config_dir, "sessions")
      @self_id = exclude_self ? ENV["CLAUDE_CODE_SESSION_ID"] : nil
    end

    def peers
      Dir.glob(File.join(dir, "*.json")).filter_map { |f| load_peer(f) }
         .reject { |p| p.session_id == @self_id }
         .sort_by { |p| p.started_at || Time.at(0) }.reverse
    end

    # ref: full sessionId, unique sessionId prefix (4+ chars), pid, or exact name.
    def find(ref)
      ref = ref.to_s
      all = peers
      hits = all.select { |p| p.session_id == ref }
      hits = all.select { |p| p.pid.to_s == ref } if hits.empty? && ref.match?(/\A\d+\z/)
      hits = all.select { |p| p.name == ref } if hits.empty?
      hits = all.select { |p| p.session_id.to_s.start_with?(ref) } if hits.empty? && ref.length >= 4
      raise NotFound, "no live session matches #{ref.inspect}" if hits.empty?
      raise Ambiguous, "#{ref.inspect} matches #{hits.size} sessions; use a sessionId (#{hits.map { |p| p.session_id[0, 8] }.join(', ')})" if hits.size > 1
      hits.first
    end

    private

    def load_peer(file)
      rec = JSON.parse(File.read(file))
      return unless rec.is_a?(Hash) && rec["sessionId"] && rec["messagingSocketPath"]
      return unless File.basename(file) == "#{rec['pid']}.json"
      return unless alive?(rec["pid"]) && File.socket?(rec["messagingSocketPath"])
      Peer.from_record(rec)
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::EPERM
      true
    rescue Errno::ESRCH, TypeError
      false
    end
  end
end
