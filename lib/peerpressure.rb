require_relative "peerpressure/version"
require_relative "peerpressure/peer"
require_relative "peerpressure/registry"
require_relative "peerpressure/target"
require_relative "peerpressure/registration"
require_relative "peerpressure/message"
require_relative "peerpressure/delivery"
require_relative "peerpressure/sender"
require_relative "peerpressure/session"
require_relative "peerpressure/cli_transport"
require_relative "peerpressure/hc"
require_relative "peerpressure/herdr"

# List and message live Claude Code and Codex sessions on this machine.
#
# Claude Code keeps one JSON record per live session in <config>/sessions/<pid>.json
# and an inbox Unix socket per session. Codex tasks join the same registry through
# the claude-uds-bridge plugin. The wire format is a Claude Code internal with no
# compatibility promise, so Sender is the only place that knows it.
module PeerPressure
  class Error < StandardError; end
  class NotFound < Error; end
  class Ambiguous < Error; end
  class Undeliverable < Error; end

  def self.list(**opts) = Registry.new(**opts).peers

  def self.find(ref, **opts) = Registry.new(**opts).find(ref)

  # Transports tried, in order, when a ref is not a Claude Code or Codex-bridge session:
  # herdr-core terminals (the desktop app), then plain herdr agents. Each is [registry, sender class].
  def self.fallbacks = [[Hc::Registry.new, Hc::Sender], [Herdr::Registry.new, Herdr::Sender]]

  # Registers this process as a peer for the duration of the send (the Codex bridge drops frames
  # from unregistered senders) and listens `wait` seconds (at least Sender::SETTLE). Returns a
  # Delivery (status :unconfirmed / :held / :denied / ...) plus any replies as `messages`.
  def self.send_message(ref, text, registry: Registry.new, from_label: "peerpressure", wait: 0, fallbacks: self.fallbacks, **opts)
    begin
      peer = registry.find(ref)
    rescue NotFound => not_found
      return send_via_fallback(ref, text, fallbacks, from_label, not_found)
    end
    Registration.open(name: from_label, config_dir: File.dirname(registry.dir)) do |reg|
      id = Sender.new(from_label: from_label, from: reg.address, **opts).deliver(peer, text)
      deadline = Time.now + [wait, Sender::SETTLE].max
      sleep 0.05 while Time.now < deadline
      messages = Array.new(reg.frames.size) { Message.parse(reg.frames.pop) }.compact
      { delivery: Delivery.from(id, messages), messages: messages.select { |m| m.kind == :message } }
    end
  end

  # No receipt exists on these transports, so the status is always :unconfirmed.
  def self.send_via_fallback(ref, text, fallbacks, from_label, not_found)
    fallbacks.each do |reg, sender_class|
      peer = reg.find(ref)
      id = sender_class.new(from_label: from_label).deliver(peer, text)
      return { delivery: Delivery.new(msg_id: id, status: :unconfirmed, receipts: []), messages: [] }
    rescue NotFound
      next
    end
    raise not_found
  end
  private_class_method :send_via_fallback
end
