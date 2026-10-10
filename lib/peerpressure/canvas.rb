require_relative "../peerpressure"

module PeerPressure
  # Canvas relay: StreamWeaver canvas forms that message a session instead of blocking it.
  # Loaded on demand (`require "peerpressure/canvas"`); nothing here is needed to list or send.
  module Canvas
    # The canvas bridge is not running, or the stream_weaver gem is not installed.
    class Unavailable < Error; end
  end
end

require_relative "canvas/formatter"
require_relative "canvas/status_view"
require_relative "canvas/stream_weaver_client"
require_relative "canvas/relay"
require_relative "canvas/lifecycle"
require_relative "canvas/demo"
