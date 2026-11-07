RSpec.describe PeerPressure::Hc do
  let(:terminals_json) do
    JSON.generate("terminals" => [
      { "address" => "t3", "agent" => "codex", "cwd" => "/w", "state" => "live", "status" => "idle" },
      { "address" => "t4", "agent" => "copilot", "name" => "copilot-ping", "cwd" => "/w", "state" => "live" },
      { "address" => "t5", "agent" => "claude-code", "state" => "finished" }
    ])
  end

  def runner(sent, send_ok: true)
    ls = terminals_json
    lambda do |*args|
      next [ls, true] if args.first == "ls"
      sent << args
      [send_ok ? "{}" : "no such terminal", send_ok]
    end
  end

  it "lists live terminals as peers, naming them by address when unnamed" do
    peers = described_class::Registry.new(runner: runner([])).peers
    expect(peers.map { |p| [p.session_id, p.name, p.kind] }).to eq([["t3", "t3", :codex], ["t4", "copilot-ping", :copilot]])
  end

  it "finds by address or exact name and refuses an unknown ref" do
    reg = described_class::Registry.new(runner: runner([]))
    expect(reg.find("copilot-ping").session_id).to eq("t4")
    expect(reg.find("t3").kind).to eq(:codex)
    expect { reg.find("nope") }.to raise_error(PeerPressure::NotFound)
  end

  it "skips terminals with no agent, so text is never typed into a shell" do
    shell = JSON.generate("terminals" => [{ "address" => "t9", "state" => "live" }])
    reg = described_class::Registry.new(runner: ->(*) { [shell, true] })
    expect(reg.peers).to eq([])
    expect { reg.find("t9") }.to raise_error(PeerPressure::NotFound)
  end

  it "refuses an agent blocked at a dialog, on both transports" do
    blocked = PeerPressure::Peer.new(session_id: "t4", name: "copilot-ping", status: "blocked")
    [described_class::Sender, PeerPressure::Herdr::Sender].each do |klass|
      sent = []
      expect { klass.new(runner: ->(*a) { sent << a; ["", true] }).deliver(blocked, "hi") }
        .to raise_error(PeerPressure::Undeliverable, /blocked at a dialog/)
      expect(sent).to be_empty
    end
  end

  it "raises Undeliverable when plain herdr refuses" do
    peer = PeerPressure::Peer.new(session_id: "rev", name: "rev", status: "idle")
    sender = PeerPressure::Herdr::Sender.new(runner: ->(*) { ["agent_blocked", false] })
    expect { sender.deliver(peer, "x") }.to raise_error(PeerPressure::Undeliverable, /agent_blocked/)
  end

  it "kills a CLI that outlives its timeout and reports failure" do
    run = PeerPressure::CliTransport.runner("sleep", timeout: 0.2)
    started = Time.now
    expect(run.call("5")).to eq(["", false])
    expect(Time.now - started).to be < 2
    expect(PeerPressure::CliTransport.runner("no-such-binary-xyz").call).to eq(["", false])
  end

  it "returns no peers when herdr-core is unavailable" do
    failing = ->(*) { ["", false] }
    expect(described_class::Registry.new(runner: failing).peers).to eq([])
  end

  it "delivers through `send`, labelled with the sender" do
    sent = []
    peer = described_class::Registry.new(runner: runner(sent)).find("t4")
    described_class::Sender.new(from_label: "canvas", runner: runner(sent)).deliver(peer, "ping")
    expect(sent).to eq([["send", "t4", "[from canvas] ping"]])
  end

  it "raises Undeliverable when herdr-core refuses" do
    peer = described_class::Registry.new(runner: runner([])).find("t4")
    sender = described_class::Sender.new(runner: runner([], send_ok: false))
    expect { sender.deliver(peer, "x") }.to raise_error(PeerPressure::Undeliverable, /no such terminal/)
  end

  it "PeerPressure.send_message falls back to hc when the Claude registry has no match" do
    sent = []
    Dir.mktmpdir do |dir|
      empty = PeerPressure::Registry.new(config_dir: dir, exclude_self: false)
      hc = described_class::Registry.new(runner: runner(sent))
      stub_const("PeerPressure::Hc::Runner", runner(sent))
      result = PeerPressure.send_message("copilot-ping", "ping", registry: empty,
                                         fallbacks: [[hc, described_class::Sender]], from_label: "me")
      expect(result[:delivery].status).to eq(:unconfirmed)
      expect(sent).to eq([["send", "t4", "[from me] ping"]])
    end
  end

  it "tries plain herdr when herdr-core has no match, and raises the original NotFound when none do" do
    herdr_sent = []
    agents = JSON.generate("result" => { "agents" => [{ "name" => "reviewer", "agent" => "claude-code", "status" => "idle" }] })
    herdr_runner = lambda do |*args|
      next [agents, true] if args[0, 2] == %w[agent list]
      herdr_sent << args
      ["{}", true]
    end
    Dir.mktmpdir do |dir|
      empty = PeerPressure::Registry.new(config_dir: dir, exclude_self: false)
      chain = [[described_class::Registry.new(runner: runner([])), described_class::Sender],
               [PeerPressure::Herdr::Registry.new(runner: herdr_runner), PeerPressure::Herdr::Sender]]
      stub_const("PeerPressure::Herdr::Runner", herdr_runner)
      PeerPressure.send_message("reviewer", "hi", registry: empty, fallbacks: chain, from_label: "me")
      expect(herdr_sent).to eq([["agent", "prompt", "reviewer", "[from me] hi"]])
      expect { PeerPressure.send_message("ghost", "hi", registry: empty, fallbacks: chain) }
        .to raise_error(PeerPressure::NotFound, /no live session matches "ghost"/)
    end
  end

  it "returns no plain-herdr peers when the list is not the assumed shape or not JSON" do
    bare = ->(*) { [JSON.generate([{ "name" => "a" }]), true] }
    junk = ->(*) { ["not json", true] }
    expect(PeerPressure::Herdr::Registry.new(runner: bare).peers).to eq([])
    expect(PeerPressure::Herdr::Registry.new(runner: junk).peers).to eq([])
  end
end
