module AgentPeers
  # An inbound frame, parsed. kind is :message (a peer wrote to us), :receipt (delivery status
  # for something we sent: held, denied, expired, delivered, dropped, refused) or :idle (a
  # notify_when_idle subscription fired).
  Message = Struct.new(:kind, :text, :from_name, :from_session, :from_address, :msg_id, :orig_msg_id, :status, :detail, :raw, keyword_init: true) do
    ENVELOPE = /\A<cross-session-message\s([^>]*)>\n?(.*?)\n?<\/cross-session-message>\z/m

    def self.parse(frame)
      return unless frame.is_a?(Hash)
      case [frame["type"], frame["action"]]
      in ["user", _] then parse_user(frame)
      in ["control", "peer_message_status"]
        new(kind: :receipt, from_address: frame["from"], orig_msg_id: frame["orig_msg_id"], status: frame["status"], raw: frame)
      in ["control", "peer_idle_notice"]
        new(kind: :idle, from_address: frame["from"], orig_msg_id: frame["orig_msg_id"], status: frame["state"], detail: frame["detail"], raw: frame)
      else nil
      end
    end

    def self.parse_user(frame)
      content = frame.dig("message", "content").to_s
      attrs = {}
      if (m = ENVELOPE.match(content))
        m[1].scan(/([\w-]+)="([^"]*)"/) { |k, v| attrs[k] = v }
        content = m[2]
      end
      new(kind: :message, text: content, from_name: attrs["from-name"], from_session: attrs["from-session"] || frame["session_id"],
          from_address: frame["from"], msg_id: frame["msg_id"], raw: frame)
    end
  end
end
