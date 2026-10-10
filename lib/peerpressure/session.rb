module PeerPressure
  # A long-lived peer: stays registered so other agents can reply to it, and keeps what arrives.
  # Use one per process (a canvas server, a worker). Replies show up through #on_message, #inbox
  # or #wait_for; delivery receipts through #receipts_for.
  #
  #   session = PeerPressure::Session.new(name: "streamweaver-canvas").start
  #   id = session.send_message("scrum master oct 8 2026", "status check?")
  #   reply = session.wait_for(from_session: session.find("scrum master oct 8 2026").session_id, timeout: 60)
  class Session
    attr_reader :name

    def initialize(name:, config_dir: ENV["CLAUDE_CONFIG_DIR"] || File.expand_path("~/.claude"), sock_dir: Registration::SOCK_DIR)
      @name = name
      @registry = Registry.new(config_dir: config_dir)
      @registration = Registration.new(name: name, config_dir: config_dir, sock_dir: sock_dir)
      @sender = nil
      @handlers = []
      @inbox = []
      @receipts = Hash.new { |h, k| h[k] = [] }
      @lock = Mutex.new
      @cond = ConditionVariable.new
    end

    def self.open(**opts)
      session = new(**opts).start
      begin
        yield session
      ensure
        session.stop
      end
    end

    def start
      @registration.start
      @sender = Sender.new(from_label: @name, from: @registration.address)
      @pump = Thread.new { pump }
      at_exit { stop }
      self
    end

    def stop
      @pump&.kill
      @pump = nil
      @registration.stop
    end

    def session_id = @registration.session_id
    def peers = @registry.peers
    def find(ref) = @registry.find(ref)

    # ref: anything Registry#find accepts, or a Peer. Returns the msg_id.
    def send_message(ref, text)
      peer = ref.is_a?(Peer) ? ref : find(ref)
      @sender.deliver(peer, text)
    end

    # Delivery for a sent msg_id, waiting up to `timeout` for a receipt (held/denied/...). With
    # no receipt the status is :unconfirmed, never "delivered".
    def delivery(msg_id, timeout: 2)
      deadline = Time.now + timeout
      sleep 0.05 while receipts_for(msg_id).empty? && Time.now < deadline
      Delivery.from(msg_id, receipts_for(msg_id))
    end

    # One :idle Message arrives when the peer next goes idle.
    def notify_when_idle(ref)
      peer = ref.is_a?(Peer) ? ref : find(ref)
      @sender.subscribe_idle(peer)
    end

    # Answers a received Message, addressing its sender by session id.
    def reply(message, text)
      raise Error, "message has no sender session" unless message.from_session
      send_message(find(message.from_session), text)
    end

    def on_message(&block)
      @lock.synchronize { @handlers << block }
      self
    end

    # Messages received so far, oldest first; drains by default.
    def inbox(drain: true)
      @lock.synchronize { drain ? @inbox.shift(@inbox.size) : @inbox.dup }
    end

    def receipts_for(msg_id) = @lock.synchronize { @receipts[msg_id].dup }

    # Blocks for the next unread message (optionally only from one session); nil on timeout.
    def wait_for(from_session: nil, timeout: 30)
      deadline = Time.now + timeout
      @lock.synchronize do
        loop do
          if (i = @inbox.index { |m| from_session.nil? || m.from_session == from_session })
            return @inbox.delete_at(i)
          end
          left = deadline - Time.now
          return nil if left <= 0
          @cond.wait(@lock, left)
        end
      end
    end

    private

    def pump
      loop do
        msg = Message.parse(@registration.frames.pop) or next
        handlers = @lock.synchronize do
          case msg.kind
          when :receipt then @receipts[msg.orig_msg_id] << msg
          else @inbox << msg
          end
          @cond.broadcast
          @handlers.dup
        end
        handlers.each { |h| h.call(msg) } if msg.kind == :message
      end
    end
  end
end
