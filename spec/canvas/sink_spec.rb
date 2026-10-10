require "peerpressure/canvas"

RSpec.describe PeerPressure::Canvas::Sink do
  include FakeFleet

  Context = Struct.new(:name, :extension_id, :payload, :event, :state, :pusher, keyword_init: true) do
    def push(dsl) = pusher.call(dsl)
  end

  class SinkFakeSession
    attr_reader :sent
    def initialize(status: :unconfirmed) = (@sent = []; @status = status)
    def send_message(peer, text) = (@sent << [peer, text]; "msg-#{@sent.size}")
    def delivery(id, timeout: 2) = PeerPressure::Delivery.new(msg_id: id, status: @status, receipts: [])
  end

  let(:id1) { "aaaa1111-0000-4000-8000-000000000000" }
  let(:registry) { PeerPressure::Registry.new(config_dir: tmp, exclude_self: false) }
  let(:session) { SinkFakeSession.new }
  let(:log) { StringIO.new }
  let(:pushed) { [] }
  let(:sink) { described_class.new(registry: registry, session: session, log: log) }

  before { register(session_id: id1, name: "scrum", pid: Process.ppid) }

  def context(payload, event)
    Context.new(name: "c1", extension_id: "peerpressure", payload: payload, event: event, state: {}, pusher: ->(dsl) { pushed << dsl })
  end

  def action(state, button: "btn_send_1")
    { type: "event", name: "c1", event: "action", data: { type: "action", button: button, state: state } }
  end

  it "turns a submit into a message to the session named by a bare session id" do
    sink.call(context(id1, action({ choice: "A", scope: "global", name: "" })))
    peer, text = session.sent.first
    expect(peer.name).to eq("scrum")
    expect(text[/Answer as JSON: (.*)\z/, 1]).to eq('{"choice":"A"}')
    expect(pushed.last).to include("Sent to scrum")
  end

  it "accepts the pinned target as JSON, and follows a /clear" do
    target = PeerPressure::Target.from_peer(registry.find(id1))
    payload = target.to_reply_to.sub("peerpressure:", "")
    register(session_id: "bbbb2222-0000-4000-8000-000000000000", name: "scrum", pid: Process.ppid) # /clear
    sink.call(context(payload, action({ choice: "B" })))
    expect(session.sent.first[0].session_id).to eq("bbbb2222-0000-4000-8000-000000000000")
  end

  it "ignores change events" do
    sink.call(context(id1, { type: "event", name: "c1", event: "change", data: { type: "change", field: "x", value: "1", state: { x: "1" } } }))
    expect(session.sent).to be_empty
    expect(pushed).to be_empty
  end

  it "keeps one relay per canvas and target, so Resend still has its last answer" do
    sink.call(context(id1, action({ choice: "A" })))
    sink.call(context(id1, action({ choice: "ignored" }, button: "btn_resend_2")))
    expect(session.sent.size).to eq(2)
    expect(session.sent.last[1]).to include('{"choice":"A"}')
  end

  it "tells the person, instead of raising, when the pinned target does not exist" do
    expect { sink.call(context("no-such-session", action({ choice: "A" }))) }.not_to raise_error
    expect(session.sent).to be_empty
    expect(pushed.last).to include("is gone").and include("choice")
    expect(log.string).to include("no live session")
  end

  it "stays quiet about a missing target on change events" do
    sink.call(context("no-such-session", { type: "event", name: "c1", event: "change", data: { type: "change", field: "x", value: "1", state: {} } }))
    expect(pushed).to be_empty
  end

  it "retries resolving a missing target on the next press" do
    sink.call(context("late-session", action({ choice: "A" })))
    expect(session.sent).to be_empty
    register(session_id: "cccc3333-0000-4000-8000-000000000000", name: "late-session", pid: Process.ppid)
    sink.call(context("late-session", action({ choice: "A" })))
    expect(session.sent.size).to eq(1)
  end

  it "serializes concurrent calls for the same canvas" do
    threads = 5.times.map { |i| Thread.new { sink.call(context(id1, action({ n: i }))) } }
    threads.each(&:join)
    expect(session.sent.size).to eq(5)
  end

  describe "the extension loader" do
    it "registers the sink with StreamWeaver under the id peerpressure" do
      registered = nil
      stub_const("StreamWeaver", Module.new)
      StreamWeaver.define_singleton_method(:register_extension) { |id, **opts| registered = [id, opts] }
      load File.expand_path("../../lib/peerpressure/stream_weaver.rb", __dir__)
      expect(registered[0]).to eq(:peerpressure)
      expect(registered[1][:canvas_event_sink]).to be_a(described_class)
    end

    it "is the loader the gemspec advertises to StreamWeaver's extension discovery" do
      spec = Gem::Specification.load(File.expand_path("../../peerpressure.gemspec", __dir__))
      expect(spec.metadata["stream_weaver.extensions.v1"]).to eq("peerpressure/stream_weaver")
      expect(File).to exist(File.expand_path("../../lib/#{spec.metadata['stream_weaver.extensions.v1']}.rb", __dir__))
    end
  end
end
