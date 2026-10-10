require "fileutils"

RSpec.describe AgentPeers::Registration do
  include FakeFleet

  let(:sock_dir) { File.join(tmp, "socks").tap { |d| FileUtils.mkdir_p(d, mode: 0o700) } }
  let(:reg) { described_class.new(name: "canvas", config_dir: tmp, sock_dir: sock_dir) }
  after { reg.stop }

  it "writes a record a Codex-style validator accepts, with a private socket" do
    reg.start
    rec = JSON.parse(File.read(File.join(sessions_dir, "#{Process.pid}.json")))
    expect(rec).to include("pid" => Process.pid, "peerProtocol" => 1, "name" => "canvas",
                           "messagingSocketPath" => reg.socket_path, "sessionId" => reg.session_id)
    expect(rec["sessionId"]).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    expect(File.stat(reg.socket_path).mode & 0o077).to eq(0)
    expect(File.stat(File.join(sessions_dir, "#{Process.pid}.json")).mode & 0o077).to eq(0)
  end

  it "shows up in the registry while open and disappears after stop" do
    reg.start
    reg_view = AgentPeers::Registry.new(config_dir: tmp, exclude_self: false)
    expect(reg_view.peers.map(&:name)).to include("canvas")
    reg.stop
    expect(reg_view.peers.map(&:name)).not_to include("canvas")
    expect(File.exist?(reg.socket_path)).to be(false)
  end

  it "encodes the socket path as the bridge's uds: address" do
    reg.start
    expect(reg.address).to eq("uds:#{reg.socket_path}")
  end

  it "collects frames written to its socket" do
    reg.start
    UNIXSocket.open(reg.socket_path) { |s| s.write(JSON.generate(type: "user", message: { content: "hi" }) + "\n") }
    expect(Timeout.timeout(2) { reg.frames.pop }.dig("message", "content")).to eq("hi")
  end
end
