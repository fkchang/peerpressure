module PeerPressure
  module Canvas
    # The only file that touches StreamWeaver. The relay talks to anything with this shape:
    # each_event(name) { |event| }, push(name, dsl), ensure_canvas(name).
    class StreamWeaverClient
      def initialize
        require "stream_weaver"
        require "stream_weaver/canvas/client"
        @client = ::StreamWeaver::Canvas::Client
        @messages = ::StreamWeaver::Canvas::Protocol::Messages
      rescue LoadError
        raise Unavailable, "the stream_weaver gem is not installed (gem install stream_weaver)"
      end

      # Holds one connection open and yields every event for `name`; returns when the bridge closes it.
      def each_event(name, &block)
        @client.each_event(name, &block)
      rescue @client::NotRunningError, @client::ConnectionError => e
        raise Unavailable, e.message
      end

      # reply_to: "peerpressure:<target>" makes the bridge itself deliver this canvas's submits (no relay
      # process). Only sent when given, so an older StreamWeaver without reply_to still works for the rest.
      def push(name, dsl, reply_to: nil)
        extra = reply_to ? { reply_to: reply_to } : {}
        @client.send_message(@messages.push(name, dsl, source_dir: nil, **extra))
      rescue ArgumentError
        raise Unavailable, "this StreamWeaver does not support reply_to; upgrade the stream_weaver gem"
      rescue @client::NotRunningError, @client::ConnectionError => e
        raise Unavailable, e.message
      end

      def ensure_canvas(name, reply_to: nil)
        extra = reply_to ? { reply_to: reply_to } : {}
        @client.ensure_bridge_running
        @client.send_message(@messages.create(name, layout: :fluid, **extra))
      rescue ArgumentError
        raise Unavailable, "this StreamWeaver does not support reply_to; upgrade the stream_weaver gem"
      rescue @client::NotRunningError, @client::ConnectionError => e
        raise Unavailable, e.message
      end
    end
  end
end
