require "fileutils"
require "timeout"

RSpec.describe AgentPeers::Session do
  include FakeFleet

  let(:sock_dir) { File.join(tmp, "socks").tap { |d| FileUtils.mkdir_p(d, mode: 0o700) } }
  let(:session) { described_class.new(name: "canvas", config_dir: tmp, sock_dir: sock_dir) }
  after { session.stop }

  def reply_frame(session, text, from_name: "scrum", from_session: "abcd1234-0000-4000-8000-000000000000")
    { type: "user", msgV: 1, msg_id: SecureRandom.uuid, from: "uds:/tmp/x.sock", session_id: session.session_id,
      message: { role: "user", content: "<cross-session-message from=\"uds:/tmp/x.sock\" from-session=\"#{from_session}\" from-name=\"#{from_name}\">\n#{text}\n</cross-session-message>" } }
  end

  def write_frame(session, frame)
    reg = JSON.parse(File.read(File.join(sessions_dir, "#{Process.pid}.json")))
    UNIXSocket.open(reg["messagingSocketPath"]) { |s| s.write(JSON.generate(frame) + "\n") }
  end

  before { session.start }

  it "stays registered and is visible to other peers" do
    names = AgentPeers::Registry.new(config_dir: tmp, exclude_self: false).peers.map(&:name)
    expect(names).to include("canvas")
  end

  it "sends from its own registered address" do
    register(session_id: "abcd1234-0000-4000-8000-000000000000", name: "target", pid: Process.ppid)
    server = servers.first
    id = session.send_message("target", "hello")
    client = server.accept
    frame = JSON.parse(client.gets)
    expect(frame).to include("msg_id" => id, "from" => session.instance_variable_get(:@registration).address)
  end

  it "parses the cross-session envelope and exposes sender and body" do
    write_frame(session, reply_frame(session, "all good"))
    msg = session.wait_for(timeout: 2)
    expect([msg.kind, msg.text, msg.from_name, msg.from_session]).to eq([:message, "all good", "scrum", "abcd1234-0000-4000-8000-000000000000"])
  end

  it "calls on_message handlers" do
    seen = Queue.new
    session.on_message { |m| seen << m.text }
    write_frame(session, reply_frame(session, "ping"))
    expect(Timeout.timeout(2) { seen.pop }).to eq("ping")
  end

  it "wait_for filters by sender and times out with nil" do
    write_frame(session, reply_frame(session, "from a", from_session: "aaaa0000-0000-4000-8000-000000000000"))
    expect(session.wait_for(from_session: "bbbb0000-0000-4000-8000-000000000000", timeout: 0.3)).to be_nil
    expect(session.wait_for(from_session: "aaaa0000-0000-4000-8000-000000000000", timeout: 1).text).to eq("from a")
  end

  it "keeps delivery receipts apart from messages" do
    oid = SecureRandom.uuid
    write_frame(session, { type: "control", msgV: 1, from: "uds:/tmp/x.sock", action: "peer_message_status", orig_msg_id: oid, status: "held" })
    Timeout.timeout(2) { sleep 0.05 until session.receipts_for(oid).any? }
    expect(session.receipts_for(oid).first.status).to eq("held")
    expect(session.inbox).to be_empty
  end

  it "reports a held message as :held, and no receipt as :unconfirmed" do
    oid = SecureRandom.uuid
    expect(session.delivery(oid, timeout: 0.1).status).to eq(:unconfirmed)
    write_frame(session, { type: "control", msgV: 1, from: "uds:/tmp/x.sock", action: "peer_message_status", orig_msg_id: oid, status: "held" })
    d = session.delivery(oid, timeout: 2)
    expect([d.status, d.held?, d.failed?]).to eq([:held, true, false])
    write_frame(session, { type: "control", msgV: 1, from: "uds:/tmp/x.sock", action: "peer_message_status", orig_msg_id: oid, status: "denied", reason: "no" })
    Timeout.timeout(2) { sleep 0.05 until session.receipts_for(oid).size == 2 }
    d = session.delivery(oid)
    expect([d.status, d.failed?, d.detail]).to eq([:denied, true, "no"])
  end

  it "surfaces an idle notice as an :idle message" do
    write_frame(session, { type: "control", msgV: 1, from: "uds:/tmp/x.sock", action: "peer_idle_notice", orig_msg_id: SecureRandom.uuid, state: "idle" })
    expect(session.wait_for(timeout: 2).kind).to eq(:idle)
  end

  it "subscribes to idle through a registered peer" do
    register(session_id: "abcd1234-0000-4000-8000-000000000000", name: "target", pid: Process.ppid)
    server = servers.first
    session.notify_when_idle("target")
    expect(JSON.parse(server.accept.gets)).to include("action" => "notify_when_idle")
  end

  it "reply addresses the sender by session id" do
    register(session_id: "abcd1234-0000-4000-8000-000000000000", name: "scrum", pid: Process.ppid)
    server = servers.first
    write_frame(session, reply_frame(session, "q?"))
    msg = session.wait_for(timeout: 2)
    session.reply(msg, "answer")
    expect(JSON.parse(server.accept.gets).dig("message", "content")).to include("answer")
  end
end
