require "peerpressure/canvas"

RSpec.describe PeerPressure::Canvas::Formatter do
  it "carries the answer as complete JSON and says where it came from" do
    text = described_class.message(canvas: "decision", button: "btn_send_1", answer: { choice: "B", notes: "iso" }, at: Time.new(2026, 10, 9, 12, 3, 4))
    expect(text).to include('"decision"').and include("btn_send_1").and include("2026-10-09 12:03:04")
    expect(text[/Answer as JSON: (.*)\z/, 1]).to eq('{"choice":"B","notes":"iso"}')
  end
end
