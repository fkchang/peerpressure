RSpec.describe AgentPeers::Sender do
  include FakeFleet

  let(:registry) { AgentPeers::Registry.new(config_dir: tmp, exclude_self: false) }

  def read_frame(server)
    client = server.accept
    JSON.parse(client.gets).tap { client.close }
  end

  it "writes one newline-terminated user frame addressed to the session" do
    register(session_id: "abcd1234-0000", name: "target")
    server = servers.first
    id = described_class.new(from_label: "canvas").deliver(registry.find("target"), "hello")
    frame = read_frame(server)
    expect(frame).to include("type" => "user", "msgV" => 1, "msg_id" => id,
                             "session_id" => "abcd1234-0000", "priority" => "next")
    expect(frame["message"]).to eq("role" => "user", "content" => "[from canvas] hello")
    expect(frame["from"]).to start_with("uds:/")
  end

  it "uses the registered address as `from` when given" do
    register(session_id: "abcd1234-0000", name: "target")
    server = servers.first
    described_class.new(from: "uds:/tmp/x.sock").deliver(registry.find("target"), "hi")
    expect(read_frame(server)["from"]).to eq("uds:/tmp/x.sock")
  end

  it "AgentPeers.send_message resolves the ref then delivers" do
    register(session_id: "abcd1234-0000", name: "target")
    server = servers.first
    result = AgentPeers.send_message("abcd", "hi", registry: registry)
    frame = read_frame(server)
    expect(frame.dig("message", "content")).to include("hi")
    expect(result[:delivery].msg_id).to eq(frame["msg_id"])
    expect(result[:delivery].status).to eq(:unconfirmed)
  end

  it "subscribe_idle writes a notify_when_idle control frame" do
    register(session_id: "abcd1234-0000", name: "target")
    server = servers.first
    id = described_class.new(from: "uds:/tmp/x.sock").subscribe_idle(registry.find("target"))
    frame = read_frame(server)
    expect(frame).to include("type" => "control", "action" => "notify_when_idle", "msg_id" => id,
                             "session_id" => "abcd1234-0000", "msgV" => 1)
  end

  it "rejects an empty message" do
    register(session_id: "abcd1234-0000", name: "target")
    expect { described_class.new.deliver(registry.find("target"), "  ") }.to raise_error(ArgumentError)
  end

  it "rejects a frame over the line limit" do
    register(session_id: "abcd1234-0000", name: "target")
    big = "x" * AgentPeers::Sender::MAX_LINE
    expect { described_class.new.deliver(registry.find("target"), big) }.to raise_error(AgentPeers::Undeliverable, /too long/)
  end

  it "raises Undeliverable when the socket disappears" do
    sock = register(session_id: "abcd1234-0000", name: "target")
    peer = registry.find("target")
    servers.each(&:close)
    File.delete(sock)
    expect { described_class.new.deliver(peer, "hi") }.to raise_error(AgentPeers::Undeliverable)
  end
end
