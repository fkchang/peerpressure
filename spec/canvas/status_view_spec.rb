require "peerpressure/canvas"

RSpec.describe PeerPressure::Canvas::StatusView do
  # Evaluates the generated DSL against a recorder, so the strings are checked after Ruby parses them.
  class DslRecorder
    attr_reader :calls
    def initialize = @calls = []
    def callout(text, **opts) = @calls << [:callout, text, opts]
    def md(text) = @calls << [:md, text]
    def button(label) = @calls << [:button, label]
  end

  def render(**kw)
    DslRecorder.new.tap { |r| r.instance_eval(described_class.dsl(**kw)) }.calls
  end

  def delivery(status, detail: nil) = PeerPressure::Delivery.new(msg_id: "m", status: status, detail: detail, receipts: [])

  it "says what happened for an unconfirmed send and keeps the answer" do
    calls = render(target_name: "scrum", answer: { choice: "A" }, delivery: delivery(:unconfirmed))
    expect(calls[0]).to eq([:callout, "Written to its inbox. No receipt means nothing objected, not proof it was read.", { tone: :success, title: "Sent to scrum" }])
    expect(calls[1][1]).to include("choice").and include("A")
    expect(calls.last).to eq([:button, "Resend"])
  end

  it "shows held as a warning" do
    expect(render(target_name: "x", answer: {}, delivery: delivery(:held))[0][2]).to eq(tone: :warning, title: "Held by x")
  end

  it "shows a denial as an error with the detail" do
    c = render(target_name: "x", answer: {}, delivery: delivery(:denied, detail: "no"))[0]
    expect(c[2][:tone]).to eq(:error)
    expect(c[1]).to include("denied").and include("(no)")
  end

  it "shows a gone session" do
    c = render(target_name: "scrum", answer: { a: 1 }, error: PeerPressure::NotFound.new("gone"))[0]
    expect(c[2]).to eq(tone: :error, title: "scrum is gone")
  end

  it "keeps hostile text inert: no interpolation, no HTML" do
    nasty = %q(a "quote" #{raise 'boom'} <script>alert(1)</script>)
    calls = render(target_name: nasty, answer: { notes: nasty }, delivery: delivery(:unconfirmed))
    expect(calls[0][2][:title]).to eq("Sent to #{nasty}")
    expect(calls[1][1]).to include("&lt;script&gt;").and include('#{raise')
    expect(calls[1][1]).not_to include("<script>")
  end
end
