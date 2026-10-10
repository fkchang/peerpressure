require "peerpressure/canvas"

RSpec.describe PeerPressure::Canvas::Demo do
  class DemoFakeClient
    attr_reader :calls
    def initialize = @calls = []
    def ensure_canvas(name, **opts) = @calls << [:ensure_canvas, name, opts]
    def push(name, dsl, **opts) = @calls << [:push, name, dsl, opts]
  end

  class DemoFakeLifecycle
    attr_reader :started
    def ensure_running(canvas, target) = (@started = [canvas, target]; [:started, 123])
  end

  let(:target) { PeerPressure::Target.new(session_id: "aaaa1111-0000-4000-8000-000000000000", pid: 5, proc_start: "x", name: "scrum") }
  let(:client) { DemoFakeClient.new }
  let(:lifecycle) { DemoFakeLifecycle.new }
  let(:out) { StringIO.new }

  it "pushes the form and starts a relay by default" do
    described_class.run(canvas: "c", target: target, client: client, lifecycle: lifecycle, out: out)
    expect(client.calls.map(&:first)).to eq(%i[ensure_canvas push])
    expect(client.calls.last[3]).to eq({})
    expect(lifecycle.started).to eq(["c", target])
    expect(out.string).to include("relay started")
  end

  it "via reply_to pins the canvas to the target and starts no relay" do
    described_class.run(canvas: "c", target: target, via: :reply_to, client: client, lifecycle: lifecycle, out: out)
    expect(client.calls[0]).to eq([:ensure_canvas, "c", { reply_to: target.to_reply_to }])
    expect(client.calls[1][3]).to eq(reply_to: target.to_reply_to)
    expect(lifecycle.started).to be_nil
    expect(out.string).to include("No relay process")
  end

  it "keeps hostile target names out of the DSL source" do
    evil = PeerPressure::Target.new(session_id: "x", pid: 1, proc_start: "y", name: %q(a" + system("x") + "))
    expect { eval("proc { #{described_class.dsl(evil.name).lines.reject { |l| l =~ /\A(header1|radio_group|text_field|button)/ }.join.gsub(/\Amd /, 'x = ')} }") }.not_to raise_error
    expect(described_class.dsl(evil.name)).not_to include(%(" + system("x"))) # the name only appears inspect-escaped
  end
end
