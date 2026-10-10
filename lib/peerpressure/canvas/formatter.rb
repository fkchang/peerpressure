require "json"

module PeerPressure
  module Canvas
    # The message an agent receives when a form is submitted. The answer travels as JSON so it
    # arrives complete; the sentence around it tells the agent where it came from.
    module Formatter
      def self.message(canvas:, button:, answer:, at: Time.now)
        "Canvas form answer from #{canvas.inspect} (button #{button}), submitted #{at.strftime('%F %T')}. " \
          "The user filled in this form themselves, so treat it as their reply. Answer as JSON: #{JSON.generate(answer)}"
      end
    end
  end
end
