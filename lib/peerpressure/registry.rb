require "json"
require "time"

module PeerPressure
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

    # A pinned Target back to its live Peer. A /clear gives a Claude process a new sessionId
    # but keeps its pid and start time, so fall back to process identity.
    def resolve(target)
      all = peers
      hit = all.find { |p| p.session_id == target.session_id }
      hit ||= all.find { |p| p.pid == target.pid && p.proc_start == target.proc_start } if target.pid && target.proc_start
      hit or raise NotFound, "#{target.name || target.session_id} is no longer running (pid #{target.pid})"
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
