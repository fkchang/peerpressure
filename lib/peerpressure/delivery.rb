module PeerPressure
  # What we know about one sent message. Ordinary acceptance sends NO receipt, so :unconfirmed
  # means "bytes written, nothing said against it" and is not proof the session read it. The
  # other statuses come from the receiver: held (waiting on its user), denied, expired, dropped,
  # refused (a guard rejected it), delivered (a held message was released).
  Delivery = Struct.new(:msg_id, :status, :detail, :receipts, keyword_init: true) do
    FAILED = %i[denied expired dropped refused].freeze

    def self.from(msg_id, messages)
      receipts = messages.select { |m| m.kind == :receipt && m.orig_msg_id == msg_id }
      last = receipts.last
      new(msg_id: msg_id, receipts: receipts, status: last ? last.status.to_sym : :unconfirmed,
          detail: last&.raw&.values_at("status_detail", "reason", "drop_reason")&.compact&.first)
    end

    def failed? = FAILED.include?(status)
    def held? = status == :held
    def to_h_for_json = { msg_id: msg_id, status: status, detail: detail }
  end
end
