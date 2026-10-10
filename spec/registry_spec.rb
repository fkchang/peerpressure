require "fileutils"

RSpec.describe PeerPressure::Registry do
  include FakeFleet

  let(:registry) { described_class.new(config_dir: tmp, exclude_self: false) }

  it "lists a live session with its kind" do
    register(session_id: "aaaa1111-0000", name: "scrum master")
    peer = registry.peers.first
    expect([peer.name, peer.kind, peer.status]).to eq(["scrum master", :claude, "idle"])
  end

  it "marks bridge-registered Codex tasks as :codex" do
    register(session_id: "bbbb2222-0000", name: "codex-x-1", entrypoint: "codex-claude-uds-bridge")
    expect(registry.peers.first.kind).to eq(:codex)
  end

  it "skips records whose process is gone or whose socket is missing" do
    register(session_id: "cccc3333-0000", name: "dead", pid: 2_999_999)
    register(session_id: "dddd4444-0000", name: "no socket", with_socket: false)
    expect(registry.peers).to be_empty
  end

  it "skips a record whose filename does not match its pid" do
    register(session_id: "eeee5555-0000", name: "x")
    File.rename(File.join(sessions_dir, "#{Process.pid}.json"), File.join(sessions_dir, "1.json"))
    expect(registry.peers).to be_empty
  end

  it "omits the calling session" do
    register(session_id: "ffff6666-0000", name: "me")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("CLAUDE_CODE_SESSION_ID").and_return("ffff6666-0000")
    expect(described_class.new(config_dir: tmp).peers).to be_empty
  end

  describe "#find" do
    before { register(session_id: "abcd1234-0000", name: "scrum master") }

    it("by full id") { expect(registry.find("abcd1234-0000").name).to eq("scrum master") }
    it("by unique prefix") { expect(registry.find("abcd").name).to eq("scrum master") }
    it("by exact name") { expect(registry.find("scrum master").session_id).to eq("abcd1234-0000") }
    it("by pid") { expect(registry.find(Process.pid.to_s).name).to eq("scrum master") }
    it("raises NotFound") { expect { registry.find("nope") }.to raise_error(PeerPressure::NotFound) }

    it "raises Ambiguous when a name matches two sessions" do
      register(session_id: "abcd9999-0000", name: "scrum master", pid: Process.ppid)
      expect { registry.find("scrum master") }.to raise_error(PeerPressure::Ambiguous, /sessionId/)
    end
  end
end
