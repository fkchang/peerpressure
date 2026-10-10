require "peerpressure/canvas"
require "fileutils"

RSpec.describe PeerPressure::Canvas::Relay do
  include FakeFleet

  Unavailable = PeerPressure::Canvas::Unavailable

  class FakeClient
    attr_reader :pushes
    def initialize(script = []) = (@script = script; @pushes = [])
    # Each entry is either an array of events to yield or an exception to raise, one per connection.
    def each_event(_name)
      step = @script.shift
      raise step if step.is_a?(Exception)
      Array(step).each { |e| yield e }
    end
    def push(name, dsl) = @pushes << [name, dsl]
  end

  class FakeSession
    attr_reader :sent
    def initialize(status: :unconfirmed) = (@sent = []; @status = status)
    def send_message(peer, text) = (@sent << [peer, text]; "msg-#{@sent.size}")
    def delivery(id, timeout: 2) = PeerPressure::Delivery.new(msg_id: id, status: @status, receipts: [])
  end

  let(:id1) { "aaaa1111-0000-4000-8000-000000000000" }
  let(:registry) { PeerPressure::Registry.new(config_dir: tmp, exclude_self: false) }
  let(:session) { FakeSession.new }
  let(:client) { FakeClient.new }
  let(:log) { StringIO.new }

  before { register(session_id: id1, name: "scrum", pid: Process.ppid) }

  def target = PeerPressure::Target.from_peer(registry.find(id1))
  def relay(**o) = described_class.new(canvas: "c1", target: target, client: client, session: session, registry: registry, retry_delay: 0, log: log, **o)
  def action(button, state) = { type: "event", name: "c1", event: "action", data: { type: "action", button: button, state: state } }
  def change(field, value) = { type: "event", name: "c1", event: "change", data: { type: "change", field: field, value: value, state: { field.to_sym => value } } }

  it "forwards a submit's answer, minus the widget's scope/name keys, and pushes a status page" do
    relay.handle(action("btn_send_to_claude_1", { choice: "A", notes: "hi", scope: "global", name: "" }))
    peer, text = session.sent.first
    expect(peer.name).to eq("scrum")
    expect(text[/Answer as JSON: (.*)\z/, 1]).to eq('{"choice":"A","notes":"hi"}')
    expect(client.pushes.last[1]).to include("Sent to scrum")
  end

  it "ignores change events" do
    relay.handle(change("choice", "A"))
    expect(session.sent).to be_empty
    expect(client.pushes).to be_empty
  end

  it "only forwards buttons matching submit:" do
    r = relay(submit: /send_to_claude/)
    r.handle(action("btn_cancel_2", { choice: "A" }))
    r.handle(action("btn_send_to_claude_1", { choice: "A" }))
    expect(session.sent.size).to eq(1)
  end

  it "Resend re-sends the last answer" do
    r = relay
    r.handle(action("btn_send_1", { choice: "A" }))
    r.handle(action("btn_resend_2", { choice: "ignored" }))
    expect(session.sent.size).to eq(2)
    expect(session.sent.last[1]).to include('{"choice":"A"}')
  end

  it "reports a held message on the page" do
    held = described_class.new(canvas: "c1", target: target, client: client, session: FakeSession.new(status: :held), registry: registry, log: log)
    held.handle(action("btn_send_1", { choice: "A" }))
    expect(client.pushes.last[1]).to include("Held by scrum")
  end

  it "follows a /clear: same process, new session id" do
    r = relay
    register(session_id: "bbbb2222-0000-4000-8000-000000000000", name: "scrum", pid: Process.ppid)
    r.handle(action("btn_send_1", { choice: "A" }))
    expect(session.sent.first[0].session_id).to eq("bbbb2222-0000-4000-8000-000000000000")
    expect(r.target.session_id).to eq("bbbb2222-0000-4000-8000-000000000000")
  end

  it "tells the person when the session is gone, and keeps their answer on the page" do
    r = relay
    File.delete(File.join(sessions_dir, "#{Process.ppid}.json"))
    r.handle(action("btn_send_1", { choice: "A" }))
    expect(session.sent).to be_empty
    expect(client.pushes.last[1]).to include("scrum is gone").and include("choice")
  end

  describe "#run" do
    it "reconnects after the bridge goes away, then keeps forwarding" do
      r = nil
      script = [Unavailable.new("bridge down"), [action("btn_send_1", { choice: "B" })]]
      c = FakeClient.new(script)
      r = described_class.new(canvas: "c1", target: target, client: c, session: session, registry: registry, retry_delay: 0, log: log)
      allow(c).to receive(:each_event).and_wrap_original do |m, *a, &blk|
        m.call(*a, &blk).tap { r.stop if script.empty? }
      end
      Timeout.timeout(5) { r.run }
      expect(session.sent.size).to eq(1)
      expect(log.string).to include("bridge down")
    end
  end

  describe "with a real session and socket" do
    let(:sock_dir) { File.join(tmp, "socks").tap { |d| FileUtils.mkdir_p(d, mode: 0o700) } }

    it "delivers one JSON frame to the target's inbox" do
      server = servers.last
      real = PeerPressure::Session.new(name: "canvas-relay:c1", config_dir: tmp, sock_dir: sock_dir).start
      r = described_class.new(canvas: "c1", target: target, client: client, session: real, registry: registry, log: log)
      r.handle(action("btn_send_1", { choice: "A", scope: "global", name: "" }))
      frame = JSON.parse(server.accept.gets)
      expect(frame.dig("message", "content")).to include("Canvas form answer from \"c1\"").and include('{"choice":"A"}')
      expect(frame["session_id"]).to eq(id1)
      real.stop
    end
  end
end
