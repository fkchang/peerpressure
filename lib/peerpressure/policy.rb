require "yaml"

module PeerPressure
  # Who may ask what. Forrest grants authority per sender name in a small YAML file; a sender
  # never grants itself anything, and a name with no entry gets info only. Example:
  #   senders:
  #     scrum master: approval
  #     dot: request
  class Policy
    DEFAULT_PATH = File.expand_path("~/.config/peerpressure/authority.yml")

    # ok: accept the message. effective: the authority it may be acted on at.
    Decision = Struct.new(:ok, :effective, :reason, keyword_init: true) do
      def to_h_for_json = { ok: ok, effective: effective, reason: reason }
    end

    def initialize(path: ENV.fetch("PEERPRESSURE_POLICY", DEFAULT_PATH), grants: nil)
      @path = path
      @grants = grants || load(path)
    end

    # The highest authority granted to a sender name (case-insensitive); :info when unlisted.
    def grant_for(name)
      level = @grants[name.to_s.downcase]
      Envelope::LEVELS.include?(level) ? level : :info
    end

    # Receiver side: what to do with an envelope. `to` is this receiver's own address when it knows
    # it. A bad or missing signature is not refused (an FYI is harmless) but is downgraded to info,
    # so it can never carry an ask; no other field is trusted until the signature holds.
    def check(envelope, to: nil, key: Key.read, now: Time.now)
      return info(true, "no envelope: plain text is info only") unless envelope
      return info(true, "signature invalid: treated as info") unless envelope.valid_signature?(key)
      return info(false, "expired at #{envelope.expires}") if envelope.expired?(now)
      return info(false, "hops #{envelope.hops} over the limit of #{Envelope::MAX_HOPS}") if envelope.hops > Envelope::MAX_HOPS
      return info(true, "addressed to #{envelope.to.inspect}, not to you: treated as info") if envelope.to && to && envelope.to != to
      if envelope.transport_from && envelope.transport_from != envelope.from
        return info(true, "relayed by #{envelope.transport_from.inspect}, signed by #{envelope.from.inspect}: treated as info")
      end

      granted = grant_for(envelope.from)
      return info(false, "#{envelope.from.inspect} is granted #{granted}, not #{envelope.authority}") if rank(envelope.authority) > rank(granted)
      Decision.new(ok: true, effective: envelope.authority, reason: "ok")
    end

    # Sender side: refuse to claim more than this sender is granted, before anything is sent.
    def check_outgoing(from, authority)
      granted = grant_for(from)
      return if rank(authority) <= rank(granted)
      raise Refused, "#{from.inspect} is granted #{granted}, cannot send #{authority} (grants live in #{@path})"
    end

    private

    def rank(level) = Envelope::LEVELS.index(level)

    # A decision that never lets the message act above info.
    def info(ok, reason) = Decision.new(ok: ok, effective: :info, reason: reason)

    def load(path)
      return {} unless File.exist?(path)
      data = YAML.safe_load_file(path) || {}
      senders = data.is_a?(Hash) ? data.fetch("senders", {}) : nil
      raise Error, "#{path} is not a valid authority file: expected `senders:` mapping names to levels" unless senders.is_a?(Hash)
      senders.to_h { |name, level| [name.to_s.downcase, level.to_s.to_sym] }
    rescue Psych::Exception => e
      raise Error, "#{path} is not a valid authority file (#{e.class})"
    end
  end
end
