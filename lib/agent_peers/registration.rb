require "json"
require "securerandom"
require "socket"
require "open3"
require "fileutils"
require "time"

module AgentPeers
  # Registers THIS process as a peer: a <config>/sessions/<pid>.json record plus an inbox socket.
  # The Codex bridge silently drops any frame whose `from` is not a registered, live peer's socket
  # address (Claude sessions do not check), so a sender must be registered while it sends. Replies
  # and delivery receipts arrive on this socket and are collected in #frames.
  class Registration
    SOCK_DIR = ENV["AGENT_PEERS_SOCK_DIR"] || "/tmp/cc-socks"

    attr_reader :session_id, :socket_path, :frames

    def self.open(**opts)
      reg = new(**opts).start
      begin
        yield reg
      ensure
        reg.stop
      end
    end

    def initialize(name: "agent_peers", config_dir: ENV["CLAUDE_CONFIG_DIR"] || File.expand_path("~/.claude"), sock_dir: SOCK_DIR)
      @name = name
      @sessions_dir = File.join(config_dir, "sessions")
      @sock_dir = sock_dir
      @session_id = SecureRandom.uuid
      @frames = Queue.new
    end

    # The address other peers see as `from`, the same encoding the bridge uses.
    def address
      "uds:" + @socket_path.gsub(/[^A-Za-z0-9:_\/.\\-]/) { |c| c.bytes.map { |b| format("%%%02X", b) }.join }
    end

    def start
      FileUtils.mkdir_p(@sock_dir, mode: 0o700)
      FileUtils.mkdir_p(@sessions_dir)
      @socket_path = File.join(@sock_dir, "#{Process.pid}.sock")
      File.delete(@socket_path) if File.socket?(@socket_path)
      @server = UNIXServer.new(@socket_path)
      File.chmod(0o600, @socket_path)
      @listener = Thread.new { accept_loop }
      write_record
      self
    end

    def stop
      @listener&.kill
      @server&.close
      File.delete(@socket_path) if @socket_path && File.socket?(@socket_path)
      File.delete(record_path) if File.exist?(record_path)
    end

    private

    def record_path = File.join(@sessions_dir, "#{Process.pid}.json")

    def write_record
      now = (Time.now.to_f * 1000).to_i
      rec = { pid: Process.pid, sessionId: @session_id, cwd: Dir.pwd, startedAt: now, procStart: proc_start,
              peerProtocol: 1, pidDomain: "darwin", kind: "interactive", entrypoint: "agent_peers",
              messagingSocketPath: @socket_path, name: @name, status: "idle", statusUpdatedAt: now, peerFeatures: [] }
      tmp = "#{record_path}.tmp"
      File.write(tmp, JSON.generate(rec), perm: 0o600)
      File.rename(tmp, record_path)
    end

    # Same value the bridge compares against: `ps -o lstart=` in the C locale and UTC.
    def proc_start
      out, = Open3.capture2({ "LC_ALL" => "C", "TZ" => "UTC" }, "ps", "-o", "lstart=", "-p", Process.pid.to_s)
      out.strip
    end

    def accept_loop
      loop do
        client = @server.accept
        Thread.new(client) do |c|
          while (line = c.gets)
            @frames << JSON.parse(line) rescue nil
          end
        ensure
          c.close
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end
  end
end
