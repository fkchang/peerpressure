module PeerPressure
  module Canvas
    # Holds the canvas event connection open and turns each submit into a message to one pinned
    # session. Nothing blocks and nothing expires: the relay is the standing listener that the
    # bridge needs (it drops events when nobody is connected), and it re-pushes a status page so
    # the person sees what happened to their answer.
    class Relay
      IGNORE_KEYS = %i[scope name].freeze # state keys the Save-as-doc widget adds to every form

      attr_reader :target

      def initialize(canvas:, target:, client:, session:, registry: Registry.new, submit: /./,
                     ignore_keys: IGNORE_KEYS, retry_delay: 2, log: $stderr)
        @canvas = canvas
        @target = target
        @client = client
        @session = session
        @registry = registry
        @submit = submit
        @ignore_keys = ignore_keys
        @retry_delay = retry_delay
        @log = log
        @stopped = false
        @last = nil
      end

      def run
        until @stopped
          begin
            @client.each_event(@canvas) { |event| handle(event) }
          rescue Unavailable => e
            say "canvas bridge unavailable (#{e.message}); retrying"
          rescue StandardError => e
            say "relay error #{e.class}: #{e.message}; retrying"
          end
          sleep @retry_delay unless @stopped # each_event returns when the bridge closes
        end
      end

      def stop = @stopped = true

      def handle(event)
        data = event[:data] || {}
        return unless data[:type].to_s == "action"

        button = data[:button].to_s
        answer = (data[:state] || {}).reject { |k, _| @ignore_keys.include?(k.to_sym) }
        if button.match?(/resend/)
          return unless (@last || !answer.empty?)
          deliver(@last ? @last[:button] : button, @last ? @last[:answer] : answer)
        elsif button.match?(@submit)
          @last = { button: button, answer: answer }
          deliver(button, answer)
        end
      end

      private

      def deliver(button, answer)
        peer = @registry.resolve(@target)
        @target = Target.from_peer(peer) # follow a /clear or rename
        id = @session.send_message(peer, Formatter.message(canvas: @canvas, button: button, answer: answer))
        delivery = @session.delivery(id, timeout: 2)
        say "forwarded #{id} to #{peer.name}: #{delivery.status}"
        push StatusView.dsl(delivery: delivery, target_name: peer.name, answer: answer)
      rescue NotFound, Undeliverable => e
        say "not delivered: #{e.message}"
        push StatusView.dsl(error: e, target_name: @target.name, answer: answer)
      end

      def push(dsl)
        @client.push(@canvas, dsl)
      rescue Unavailable => e
        say "could not update the canvas: #{e.message}"
      end

      def say(text) = @log.puts("[#{Time.now.strftime('%T')}] canvas-relay #{@canvas}: #{text}")
    end
  end
end
