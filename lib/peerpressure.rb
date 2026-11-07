require_relative "peerpressure/version"
require_relative "peerpressure/peer"
require_relative "peerpressure/registry"
require_relative "peerpressure/target"
require_relative "peerpressure/registration"
require_relative "peerpressure/message"
require_relative "peerpressure/delivery"
require_relative "peerpressure/sender"
require_relative "peerpressure/session"
require_relative "peerpressure/envelope"
require_relative "peerpressure/policy"
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
  class Refused < Error; end # the sender is not granted the authority it tried to claim
  DEFAULT_LABEL = "peerpressure".freeze # from_label when the caller names none: never eligible for a grant

  def self.list(**opts) = Registry.new(**opts).peers

  def self.find(ref, **opts) = Registry.new(**opts).find(ref)

  # Transports tried, in order, when a ref is not a Claude Code or Codex-bridge session:
  # herdr-core terminals (the desktop app), then plain herdr agents. Each is [registry, sender class].
  def self.fallbacks = [[Hc::Registry.new, Hc::Sender], [Herdr::Registry.new, Herdr::Sender]]

  # Registers this process as a peer for the duration of the send (the Codex bridge drops frames
  # from unregistered senders) and listens `wait` seconds (at least Sender::SETTLE). Returns a
  # Delivery (status :unconfirmed / :held / :denied / ...) plus any replies as `messages`.
  #
  # authority: (:info / :request / :approval), reply_to: (a received Envelope) or ref:/hops: wrap the
  # text in a signed Envelope. The sender must be granted that authority by the Policy, else Refused
  # is raised before anything is sent. With none of them, the text goes out plain, as before.
  def self.send_message(ref, text, registry: Registry.new, from_label: DEFAULT_LABEL, wait: 0, fallbacks: self.fallbacks,
                        authority: nil, reply_to: nil, policy: nil, **opts)
    refuse_forwarded_envelope(text)
    begin
      peer = registry.find(ref)
    rescue NotFound => not_found
      return send_via_fallback(ref, text, fallbacks, from_label, not_found) do |fallback_peer|
        wrap_envelope(text, from: from_label, to: fallback_peer.session_id, authority: authority, reply_to: reply_to, policy: policy)
      end
    end
    text = wrap_envelope(text, from: from_label, to: peer.session_id, authority: authority, reply_to: reply_to, policy: policy)
    Registration.open(name: from_label, config_dir: File.dirname(registry.dir)) do |reg|
      id = Sender.new(from_label: from_label, from: reg.address, **opts).deliver(peer, text)
      deadline = Time.now + [wait, Sender::SETTLE].max
      sleep 0.05 while Time.now < deadline
      messages = Array.new(reg.frames.size) { Message.parse(reg.frames.pop) }.compact
      { delivery: Delivery.from(id, messages), messages: messages.select { |m| m.kind == :message } }
    end
  end

  # A received envelope pasted back out would reach a second recipient still signed by its original
  # sender, with its authority and hop count intact. Answer with --reply-to instead.
  def self.refuse_forwarded_envelope(text)
    raise Refused, "text already carries an envelope; answer it with reply_to: instead of forwarding it" if Envelope.parse(text)
  end
  private_class_method :refuse_forwarded_envelope

  def self.wrap_envelope(text, from:, to:, authority:, reply_to:, policy:)
    return text unless authority || reply_to
    level = (authority || :info).to_sym
    raise Refused, "set a sender name (from_label) to claim #{level}" if level != :info && from == DEFAULT_LABEL
    (policy || Policy.new).check_outgoing(from, level)
    env = reply_to ? Envelope.reply(reply_to, from: from, to: to, body: text, authority: level) : Envelope.build(from: from, to: to, body: text, authority: level)
    raise Refused, "hops #{env.hops} is over the limit of #{Envelope::MAX_HOPS}; not forwarding" if env.hops > Envelope::MAX_HOPS
    env.to_text
  end
  private_class_method :wrap_envelope

  # No receipt exists on these transports, so the status is always :unconfirmed. The block, when
  # given, turns the text into what is actually sent to the peer that was found.
  def self.send_via_fallback(ref, text, fallbacks, from_label, not_found)
    fallbacks.each do |reg, sender_class|
      peer = reg.find(ref)
      payload = block_given? ? yield(peer) : text
      id = sender_class.new(from_label: from_label).deliver(peer, payload)
      return { delivery: Delivery.new(msg_id: id, status: :unconfirmed, receipts: []), messages: [] }
    rescue NotFound
      next
    end
    raise not_found
  end
  private_class_method :send_via_fallback
end
