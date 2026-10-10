RSpec.describe PeerPressure::Target do
  include FakeFleet

  let(:registry) { PeerPressure::Registry.new(config_dir: tmp, exclude_self: false) }
  let(:id1) { "aaaa1111-0000-4000-8000-000000000000" }
  let(:id2) { "bbbb2222-0000-4000-8000-000000000000" }

  it "captures session id and process identity from a peer" do
    register(session_id: id1, name: "scrum", pid: Process.ppid)
    t = described_class.from_peer(registry.find(id1))
    expect([t.session_id, t.pid, t.proc_start, t.name]).to eq([id1, Process.ppid, "Fri Oct  9 23:18:03 2026", "scrum"])
  end

  it "resolves by session id" do
    register(session_id: id1, name: "scrum", pid: Process.ppid)
    t = described_class.from_peer(registry.find(id1))
    expect(registry.resolve(t).session_id).to eq(id1)
  end

  it "survives a /clear: same process, new session id" do
    register(session_id: id1, name: "scrum", pid: Process.ppid)
    t = described_class.from_peer(registry.find(id1))
    register(session_id: id2, name: "scrum", pid: Process.ppid)
    expect(registry.resolve(t).session_id).to eq(id2)
  end

  it "refuses a recycled pid (different process start time)" do
    register(session_id: id1, name: "scrum", pid: Process.ppid)
    t = described_class.from_peer(registry.find(id1))
    register(session_id: id2, name: "other", pid: Process.ppid, proc_start: "Sat Oct 10 01:00:00 2026")
    expect { registry.resolve(t) }.to raise_error(PeerPressure::NotFound, /no longer running/)
  end

  it "raises NotFound when the session is gone" do
    register(session_id: id1, name: "scrum", pid: Process.ppid)
    t = described_class.from_peer(registry.find(id1))
    File.delete(File.join(sessions_dir, "#{Process.ppid}.json"))
    expect { registry.resolve(t) }.to raise_error(PeerPressure::NotFound)
  end

  describe ".current" do
    it "uses CLAUDE_CODE_SESSION_ID" do
      register(session_id: id1, name: "scrum", pid: Process.ppid)
      expect(described_class.current(registry: registry, env: { "CLAUDE_CODE_SESSION_ID" => id1 }).name).to eq("scrum")
    end

    it "explains itself outside a Claude Code session" do
      expect { described_class.current(registry: registry, env: {}) }.to raise_error(PeerPressure::Error, /CLAUDE_CODE_SESSION_ID/)
    end
  end

  describe ".parse and #to_reply_to" do
    it "round-trips the JSON payload of a reply_to value" do
      t = described_class.new(session_id: id1, pid: 5, proc_start: "x", name: "n")
      payload = t.to_reply_to.delete_prefix("peerpressure:")
      expect(described_class.parse(payload, registry: registry)).to eq(t)
    end

    it "resolves a bare ref through the registry" do
      register(session_id: id1, name: "scrum", pid: Process.ppid)
      expect(described_class.parse("scrum", registry: registry).session_id).to eq(id1)
    end

    it "explains an empty or malformed payload" do
      expect { described_class.parse("  ", registry: registry) }.to raise_error(PeerPressure::Error, /no target/)
      expect { described_class.parse("{nope", registry: registry) }.to raise_error(PeerPressure::Error, /not valid JSON/)
    end
  end

  it "round-trips through a hash" do
    t = described_class.new(session_id: id1, pid: 5, proc_start: "x", name: "n")
    expect(described_class.from_h(t.to_h.transform_keys(&:to_s))).to eq(t)
  end
end
