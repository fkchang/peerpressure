require "cgi"

module PeerPressure
  module Canvas
    # The page the relay pushes after a submit, so a press that did not land never looks like
    # one that did. Every dynamic string goes through #inspect (never interpolated into DSL
    # source) and values are HTML-escaped before they reach markdown.
    module StatusView
      def self.dsl(target_name:, answer:, delivery: nil, error: nil)
        title, tone, body = describe(target_name, delivery, error)
        [
          "callout(#{body.inspect}, tone: #{tone.inspect}, title: #{title.inspect})",
          "md #{answer_markdown(answer).inspect}",
          'button "Resend"'
        ].join("\n")
      end

      def self.describe(name, delivery, error)
        return error_text(name, error) if error
        case delivery.status
        when :unconfirmed
          ["Sent to #{name}", :success, "Written to its inbox. No receipt means nothing objected, not proof it was read."]
        when :delivered
          ["Delivered to #{name}", :success, "The session accepted it."]
        when :held
          ["Held by #{name}", :warning, "That session is waiting for its user to approve this message. Your answer is saved below."]
        else
          detail = delivery.detail ? " (#{delivery.detail})" : ""
          ["Not delivered", :error, "#{name} #{delivery.status}#{detail}. Your answer is saved below. Resend tries again."]
        end
      end

      def self.error_text(name, error)
        case error
        when NotFound then ["#{name} is gone", :error, "That session is no longer running. Your answer is saved below. Resend tries again, or paste it into another session."]
        else ["Could not deliver", :error, "#{error.message}. Your answer is saved below."]
        end
      end

      def self.answer_markdown(answer)
        lines = answer.map { |k, v| "- **#{CGI.escapeHTML(k.to_s)}**: #{CGI.escapeHTML(v.to_s)}" }
        "Your answer (kept here):\n\n#{lines.join("\n")}"
      end
    end
  end
end
