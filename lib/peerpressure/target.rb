module PeerPressure
  # A session pinned by identity, not by whatever "current" means at click time. Holds the
  # sessionId AND the process (pid + start time), so it survives a /clear (new sessionId, same
  # process) and refuses a recycled pid.
  Target = Struct.new(:session_id, :pid, :proc_start, :name, keyword_init: true) do
    def self.from_peer(peer)
      new(session_id: peer.session_id, pid: peer.pid, proc_start: peer.proc_start, name: peer.name)
    end

    # The session this process is running inside of (Claude Code exports CLAUDE_CODE_SESSION_ID).
    def self.current(registry: Registry.new(exclude_self: false), env: ENV)
      id = env["CLAUDE_CODE_SESSION_ID"] or
        raise Error, "not inside a Claude Code session (CLAUDE_CODE_SESSION_ID is unset); pass a target explicitly"
      from_peer(registry.find(id))
    end

    def self.from_h(hash) = new(**hash.transform_keys(&:to_sym).slice(:session_id, :pid, :proc_start, :name))
  end
end
