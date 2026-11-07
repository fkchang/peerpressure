require "cgi"
require "fileutils"
require "json"
require "openssl"
require "securerandom"
require "time"

module PeerPressure
  # The shared secret that signs envelopes. A header typed by hand (by an agent, or pasted from
  # somewhere) carries no valid signature, so it can claim no authority. Anything running as this
  # user can read the file, so this proves "went through peerpressure tooling", not identity
  # against a hostile local process.
  module Key
    DEFAULT_PATH = File.expand_path("~/.config/peerpressure/key")

    def self.path = ENV.fetch("PEERPRESSURE_KEY_FILE", DEFAULT_PATH)

    # Creates a random 0600 key on first use. The create is atomic (hard link of a finished temp
    # file), so two first callers cannot end up with different keys and no reader sees a partial one.
    def self.read(path = self.path)
      create(path) unless File.exist?(path)
      key = File.read(path).strip
      raise Error, "key file #{path} is empty; delete it to have a new one made" if key.empty?
      key
    end

    def self.create(path)
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      tmp = "#{path}.#{Process.pid}.#{SecureRandom.hex(4)}.tmp"
      File.write(tmp, SecureRandom.hex(32), perm: 0o600)
      File.link(tmp, path)
    rescue Errno::EEXIST
      nil # another process created it first; use theirs
    ensure
      File.delete(tmp) if tmp && File.exist?(tmp)
    end
    private_class_method :create
  end

  # A message with who it is from, who it is for, what it is allowed to ask, and limits that stop
  # loops. On the wire it is a one-line header before the text:
  #   [pp v1 id=… from=… to=… authority=request hops=1 exp=… ref=… sig=…] the text
  # authority: info (FYI, always accepted), request (asks the receiver to act), approval (asks
  # for or grants a decision). `to` is the recipient's address, so an envelope forwarded to someone
  # else fails the check. hops counts replies in a chain; ref ties a reply to its ask.
  class Envelope
    LEVELS = %i[info request approval].freeze
    MAX_HOPS = 3
    DEFAULT_TTL = 3600 # seconds an envelope stays valid
    SIG_HEX_LENGTH = 64 # hex characters in an HMAC-SHA256
    HEADER = /\A(?:\[from ([^\]]*)\] )?\[pp v1 ([^\]]*)\] ?(.*)\z/m

    # transport_from: the name in the "[from X]" prefix the transport added, when there was one.
    attr_reader :id, :from, :to, :authority, :hops, :ref, :expires, :body, :sig, :transport_from

    def initialize(id:, from:, authority:, hops:, ref:, expires:, body:, to: nil, sig: nil, transport_from: nil)
      raise ArgumentError, "unknown authority #{authority.inspect}" unless LEVELS.include?(authority)
      raise ArgumentError, "hops must be a count, got #{hops.inspect}" unless hops.is_a?(Integer) && hops >= 0
      @id, @from, @to, @authority, @hops, @ref, @expires, @body, @sig, @transport_from =
        id, from, to, authority, hops, ref, expires, body, sig, transport_from
    end

    def self.build(from:, body:, to: nil, authority: :info, ref: nil, hops: 0, ttl: DEFAULT_TTL, now: Time.now, key: Key.read)
      env = new(id: SecureRandom.hex(4), from: from, to: to, authority: authority.to_sym, hops: hops, ref: ref,
                expires: (now + ttl).utc.iso8601, body: body)
      env.signed(key)
    end

    # An answer to a received envelope: same ref (or its id), one more hop, info unless stated.
    # The received envelope must carry a valid signature, or its hop count could be forged.
    def self.reply(to_envelope, from:, body:, to: nil, authority: :info, key: Key.read, **opts)
      raise Refused, "the envelope being answered has an invalid signature" unless to_envelope.valid_signature?(key)
      build(from: from, to: to, body: body, authority: authority, ref: to_envelope.ref || to_envelope.id,
            hops: to_envelope.hops + 1, key: key, **opts)
    end

    # nil when the text carries no (readable) envelope header: plain text is just info.
    def self.parse(text)
      match = HEADER.match(text.to_s) or return
      fields = match[2].split.to_h { |pair| pair.split("=", 2) }.transform_values { |v| CGI.unescape(v.to_s) }
      new(id: fields["id"], from: fields["from"], to: fields["to"], authority: fields["authority"].to_s.to_sym,
          hops: Integer(fields["hops"], exception: false), ref: fields["ref"], expires: fields["exp"], body: match[3],
          sig: fields["sig"], transport_from: match[1])
    rescue ArgumentError
      nil
    end

    def signed(key) = self.class.new(**to_h, sig: sign(key))

    def valid_signature?(key) = sig.to_s.size == SIG_HEX_LENGTH && OpenSSL.fixed_length_secure_compare(sign(key), sig)

    # An unreadable expiry counts as expired.
    def expired?(now = Time.now)
      Time.parse(expires.to_s) < now
    rescue ArgumentError
      true
    end

    def to_text
      fields = { id: id, from: from, to: to, authority: authority, hops: hops, exp: expires, ref: ref, sig: sig }.compact
      "[pp v1 #{fields.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join(' ')}] #{body}" # escaped: names contain spaces
    end

    def to_h = { id: id, from: from, to: to, authority: authority, hops: hops, ref: ref, expires: expires, body: body }

    private

    # Covers every field and a digest of the body, so neither can be altered after signing. The body
    # is stripped first: a message read back from a file or stdin gains a trailing newline. A JSON
    # array keeps field boundaries unambiguous (an empty ref and a missing one differ).
    def sign(key)
      canon = JSON.generate(["v1", id, from, to, authority, hops, ref, expires, OpenSSL::Digest::SHA256.hexdigest(body.to_s.strip)])
      OpenSSL::HMAC.hexdigest("SHA256", key, canon)
    end
  end
end
