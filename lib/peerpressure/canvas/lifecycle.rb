require "json"
require "rbconfig"
require "fileutils"

module PeerPressure
  module Canvas
    # One relay per canvas. The relay process writes ~/.peerpressure/relays/<canvas>.json when it
    # starts and removes it when it ends; `ensure_running` makes starting one idempotent so an
    # agent can call it every time it pushes a form.
    class Lifecycle
      EXE = File.expand_path("../../../exe/peer", __dir__)

      def initialize(home: ENV["PEERPRESSURE_HOME"] || File.expand_path("~/.peerpressure"))
        @dir = File.join(home, "relays")
      end

      def record(canvas)
        JSON.parse(File.read(path(canvas)))
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      def list = Dir.glob(File.join(@dir, "*.json")).filter_map { |f| record(File.basename(f, ".json")) }.select { |r| alive?(r) }

      def running?(canvas)
        (rec = record(canvas)) ? alive?(rec) : false
      end

      # Called by the relay process itself.
      def write(canvas, target:, log: nil)
        FileUtils.mkdir_p(@dir)
        File.write(path(canvas), JSON.generate(canvas: canvas, pid: Process.pid, started_at: Time.now.to_i, log: log, target: target.to_h))
      end

      def remove(canvas)
        rec = record(canvas)
        File.delete(path(canvas)) if rec && rec["pid"] == Process.pid
      rescue Errno::ENOENT
        nil
      end

      def stop(canvas)
        rec = record(canvas) or return false
        Process.kill("TERM", rec["pid"]) if alive?(rec)
        File.delete(path(canvas)) if File.exist?(path(canvas))
        true
      rescue Errno::ESRCH
        true
      end

      # :already when a relay for the same session process is up, else (re)starts one detached.
      def ensure_running(canvas, target)
        if (rec = record(canvas)) && alive?(rec)
          same = rec.dig("target", "pid") == target.pid && rec.dig("target", "proc_start") == target.proc_start
          return [:already, rec["pid"]] if same
          stop(canvas)
        end
        [:started, start(canvas, target)]
      end

      def start(canvas, target)
        FileUtils.mkdir_p(@dir)
        log = File.join(@dir, "#{canvas}.log")
        pid = Process.spawn(RbConfig.ruby, EXE, "canvas-relay", canvas, "--to", target.session_id, "--foreground",
                            out: [log, "a"], err: [log, "a"], pgroup: true)
        Process.detach(pid)
        pid
      end

      private

      def path(canvas) = File.join(@dir, "#{canvas}.json")

      def alive?(rec)
        Process.kill(0, rec["pid"])
        `ps -o command= -p #{rec['pid'].to_i} 2>/dev/null`.include?("canvas-relay")
      rescue Errno::ESRCH, Errno::EPERM, TypeError
        false
      end
    end
  end
end
