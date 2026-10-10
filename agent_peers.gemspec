require_relative "lib/agent_peers/version"

Gem::Specification.new do |spec|
  spec.name = "agent_peers"
  spec.version = AgentPeers::VERSION
  spec.authors = ["Forrest Chang"]
  spec.summary = "List and message live Claude Code and Codex sessions from Ruby"
  spec.files = Dir.glob("lib/**/*") + Dir.glob("exe/**/*") + ["README.md"]
  spec.bindir = "exe"
  spec.executables = ["agent-peers"]
  spec.required_ruby_version = ">= 3.2"

  # json lazily loads ostruct; declaring it silences the Ruby 3.5 deprecation warning.
  spec.add_dependency "ostruct"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
