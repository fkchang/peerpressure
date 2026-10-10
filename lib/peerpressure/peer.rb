module PeerPressure
  # One live session. kind is :claude or :codex (Codex tasks registered by the bridge
  # plugin carry entrypoint "codex-claude-uds-bridge").
  Peer = Struct.new(:session_id, :name, :kind, :pid, :cwd, :status, :started_at, :socket_path, :entrypoint, :proc_start, keyword_init: true) do
    CODEX_ENTRYPOINT = "codex-claude-uds-bridge".freeze

    def self.from_record(rec)
      new(
        session_id: rec["sessionId"], name: rec["name"], pid: rec["pid"], cwd: rec["cwd"],
        status: rec["status"], entrypoint: rec["entrypoint"], proc_start: rec["procStart"], socket_path: rec["messagingSocketPath"],
        kind: rec["entrypoint"] == CODEX_ENTRYPOINT ? :codex : :claude,
        started_at: rec["startedAt"] && Time.at(rec["startedAt"] / 1000.0)
      )
    end

    def idle? = status == "idle"

    def to_h_for_json
      to_h.merge(started_at: started_at&.iso8601)
    end
  end
end
