require_relative "agent_peers/version"
require_relative "agent_peers/peer"
require_relative "agent_peers/registry"
require_relative "agent_peers/registration"
require_relative "agent_peers/message"
require_relative "agent_peers/delivery"
require_relative "agent_peers/sender"
require_relative "agent_peers/session"

# List and message live Claude Code and Codex sessions on this machine.
#
# Claude Code keeps one JSON record per live session in <config>/sessions/<pid>.json
# and an inbox Unix socket per session. Codex tasks join the same registry through
# the claude-uds-bridge plugin. The wire format is a Claude Code internal with no
# compatibility promise, so Sender is the only place that knows it.
module AgentPeers
  class Error < StandardError; end
  class NotFound < Error; end
  class Ambiguous < Error; end
  class Undeliverable < Error; end

  def self.list(**opts) = Registry.new(**opts).peers

  def self.find(ref, **opts) = Registry.new(**opts).find(ref)

  # Registers this process as a peer for the duration of the send (the Codex bridge drops frames
  # from unregistered senders) and listens `wait` seconds (at least Sender::SETTLE). Returns a
  # Delivery (status :unconfirmed / :held / :denied / ...) plus any replies as `messages`.
  def self.send_message(ref, text, registry: Registry.new, from_label: "agent_peers", wait: 0, **opts)
    peer = registry.find(ref)
    Registration.open(name: from_label, config_dir: File.dirname(registry.dir)) do |reg|
      id = Sender.new(from_label: from_label, from: reg.address, **opts).deliver(peer, text)
      deadline = Time.now + [wait, Sender::SETTLE].max
      sleep 0.05 while Time.now < deadline
      messages = Array.new(reg.frames.size) { Message.parse(reg.frames.pop) }.compact
      { delivery: Delivery.from(id, messages), messages: messages.select { |m| m.kind == :message } }
    end
  end
end
