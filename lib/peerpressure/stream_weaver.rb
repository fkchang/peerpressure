# Loaded by StreamWeaver's extension discovery (gemspec metadata `stream_weaver.extensions.v1`),
# inside the canvas bridge process. Registers the sink that turns a canvas whose reply_to is
# "peerpressure:<target>" into messages to that session. Needs StreamWeaver 0.3.3+ (canvas_event_sink).
require "peerpressure"
require "peerpressure/canvas"

StreamWeaver.register_extension(:peerpressure, canvas_event_sink: PeerPressure::Canvas::Sink.new)
