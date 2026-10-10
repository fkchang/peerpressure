$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "peerpressure"
require "tmpdir"
require "json"
require "socket"
require "timeout"

# A throwaway config dir plus real Unix sockets, so specs never touch live sessions.
module FakeFleet
  def self.included(base)
    base.let(:tmp) { Dir.mktmpdir("peerpressure") }
    base.let(:sessions_dir) { FileUtils.mkdir_p(File.join(tmp, "sessions")).first }
    base.let(:servers) { [] }
    base.after { servers.each(&:close); FileUtils.rm_rf(tmp) }
  end

  # Registers a fake session whose pid is this test process (so it counts as alive).
  def register(session_id:, name:, entrypoint: "cli", pid: Process.pid, started_at: 1_791_000_000_000, with_socket: true, proc_start: "Fri Oct  9 23:18:03 2026")
    sock = File.join(tmp, "#{pid}-#{session_id[0, 4]}.sock")
    if with_socket
      servers << UNIXServer.new(sock)
    end
    File.write(File.join(sessions_dir, "#{pid}.json"), JSON.generate(
      pid: pid, sessionId: session_id, name: name, cwd: "/x", entrypoint: entrypoint,
      status: "idle", startedAt: started_at, procStart: proc_start, messagingSocketPath: sock
    ))
    sock
  end
end
