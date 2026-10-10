require "peerpressure/canvas"

RSpec.describe PeerPressure::Canvas::Lifecycle do
  let(:home) { Dir.mktmpdir("pp-home") }
  let(:lifecycle) { described_class.new(home: home) }
  let(:target) { PeerPressure::Target.new(session_id: "aaaa1111-0000-4000-8000-000000000000", pid: 42, proc_start: "x", name: "scrum") }
  after { FileUtils.rm_rf(home) }

  # A real process whose command line looks like a relay, so the liveness check has something to find.
  def fake_relay_process(canvas) = Process.spawn("ruby", "-e", "sleep 30", "canvas-relay", canvas, out: File::NULL, err: File::NULL)

  it "has no record before anything runs" do
    expect(lifecycle.record("c1")).to be_nil
    expect(lifecycle.running?("c1")).to be(false)
  end

  it "reports a relay as running only while its process is alive and is a relay" do
    pid = fake_relay_process("c1")
    FileUtils.mkdir_p(File.join(home, "relays"))
    File.write(File.join(home, "relays", "c1.json"), JSON.generate(canvas: "c1", pid: pid, target: target.to_h))
    expect(lifecycle.running?("c1")).to be(true)
    expect(lifecycle.list.map { |r| r["canvas"] }).to eq(["c1"])
    Process.kill("TERM", pid); Process.wait(pid)
    expect(lifecycle.running?("c1")).to be(false)
  end

  it "does not mistake an unrelated live pid for a relay" do
    FileUtils.mkdir_p(File.join(home, "relays"))
    File.write(File.join(home, "relays", "c1.json"), JSON.generate(canvas: "c1", pid: Process.pid, target: target.to_h))
    expect(lifecycle.running?("c1")).to be(false)
  end

  it "ensure_running is a no-op for the same session process" do
    pid = fake_relay_process("c1")
    FileUtils.mkdir_p(File.join(home, "relays"))
    File.write(File.join(home, "relays", "c1.json"), JSON.generate(canvas: "c1", pid: pid, target: target.to_h))
    expect(lifecycle.ensure_running("c1", target)).to eq([:already, pid])
    Process.kill("TERM", pid); Process.wait(pid)
  end

  it "stop terminates the relay and removes its record" do
    pid = fake_relay_process("c1")
    FileUtils.mkdir_p(File.join(home, "relays"))
    File.write(File.join(home, "relays", "c1.json"), JSON.generate(canvas: "c1", pid: pid, target: target.to_h))
    expect(lifecycle.stop("c1")).to be(true)
    Process.wait(pid)
    expect(lifecycle.record("c1")).to be_nil
  end

  it "only the owning process removes its own record" do
    FileUtils.mkdir_p(File.join(home, "relays"))
    File.write(File.join(home, "relays", "c1.json"), JSON.generate(canvas: "c1", pid: 99_999, target: target.to_h))
    lifecycle.remove("c1")
    expect(lifecycle.record("c1")).not_to be_nil
  end
end
