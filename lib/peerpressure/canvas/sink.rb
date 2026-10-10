module PeerPressure
  module Canvas
    # StreamWeaver's canvas_event_sink for `reply_to: "peerpressure:<target>"`. The canvas bridge
    # calls it with each browser event of a session pinned to a recipient; it runs the same Relay
    # logic as `peer canvas-relay`, but inside the bridge, so there is no relay process to keep
    # alive and a form can never time out. The bridge hands every sink call its own thread, so
    # each relay is serialized with a lock.
    class Sink
      # The relay's "client", bound to the bridge's own push instead of a socket to the bridge.
      class ContextClient
        attr_writer :pusher

        def push(_canvas, dsl) = @pusher.call(dsl)
      end

      def initialize(registry: Registry.new(exclude_self: false), session: nil, log: $stderr)
        @registry = registry
        @session = session
        @log = log
        @relays = {}
        @lock = Mutex.new
      end

      def call(context)
        entry = relay_for(context) or return
        entry[:lock].synchronize do
          entry[:client].pusher = context.pusher
          entry[:relay].handle(context.event)
        end
      end

      private

      # One relay per (canvas, target) so a Resend still has its last answer. A target that cannot
      # be resolved yet is retried on the next press; the person is told instead of left guessing.
      def relay_for(context)
        key = [context.name, context.payload]
        @lock.synchronize do
          return @relays[key] if @relays[key]

          target = begin
            Target.parse(context.payload, registry: @registry)
          rescue Error => e
            explain(context, e)
            return nil
          end
          client = ContextClient.new
          relay = Relay.new(canvas: context.name, target: target, client: client, session: shared_session,
                            registry: @registry, log: @log)
          @relays[key] = { relay: relay, client: client, lock: Mutex.new }
        end
      end

      def explain(context, error)
        data = context.event[:data] || {}
        return unless data[:type].to_s == "action"

        answer = (data[:state] || {}).reject { |k, _| Relay::IGNORE_KEYS.include?(k.to_sym) }
        context.push(StatusView.dsl(error: error, target_name: "the session this form was pinned to", answer: answer))
        @log.puts("canvas-sink #{context.name}: #{error.message}")
      end

      # One registered peer for the whole bridge process, so replies and receipts have somewhere to land.
      def shared_session
        @session ||= Session.new(name: "streamweaver-canvas").start
      end
    end
  end
end
