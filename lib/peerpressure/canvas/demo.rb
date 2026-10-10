module PeerPressure
  module Canvas
    # `peer demo`: push a form pinned to the calling session, start its relay, and get out of the
    # way. The session ends its turn; the answer arrives later as a message, with nothing polling.
    module Demo
      def self.dsl(target_name)
        <<~RUBY
          header1 "peerpressure demo: ask without blocking"
          md #{"This form belongs to **#{target_name}**. That session is not waiting on it, not polling it and not blocked. Submit whenever you like and your answer shows up in that session as a message. Close the session first and submit anyway to see what a miss looks like.".inspect}
          radio_group :choice, ["A: ship it today", "B: wait for review"]
          text_field :notes, placeholder: "anything the agent should know"
          button "Send to Claude"
        RUBY
      end

      # via: :relay starts a standing relay process (works with any StreamWeaver); via: :reply_to asks the
      # bridge to deliver submits itself (needs StreamWeaver with reply_to and this gem installed beside it).
      def self.run(canvas:, target:, via: :relay, client: StreamWeaverClient.new, lifecycle: Lifecycle.new, out: $stdout)
        if via == :reply_to
          client.ensure_canvas(canvas, reply_to: target.to_reply_to)
          client.push(canvas, dsl(target.name), reply_to: target.to_reply_to)
          out.puts "Form is on canvas #{canvas.inspect}; the canvas bridge delivers submits to #{target.name}. No relay process."
        else
          client.ensure_canvas(canvas)
          client.push(canvas, dsl(target.name))
          state, pid = lifecycle.ensure_running(canvas, target)
          out.puts "Form is on canvas #{canvas.inspect}, pinned to #{target.name} (relay #{state}, pid #{pid})."
        end
        out.puts "Open it with: streamweaver canvas-raise #{canvas}"
        out.puts "End your turn now. The answer arrives as a message; do not poll the canvas."
      end
    end
  end
end
