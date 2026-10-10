require_relative "lib/peerpressure/version"

Gem::Specification.new do |spec|
  spec.name = "peerpressure"
  spec.version = PeerPressure::VERSION
  spec.authors = ["Forrest Chang"]
  spec.summary = "Message other AI agents on your machine: list and message live Claude Code and Codex sessions"
  spec.description = "List live Claude Code and Codex sessions, send them messages, and hear back, from Ruby or the " \
                     "peer CLI. Idle sessions wake up and act. Honest delivery status (held, denied, expired) instead of " \
                     "a fake 'sent'. Local Unix sockets, same user, no network."
  spec.homepage = "https://github.com/fkchang/peerpressure"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "CHANGELOG.md", "LICENSE", "docs/for_llms.md"]
  spec.bindir = "exe"
  spec.executables = ["peer"]

  # json lazily loads ostruct; declaring it silences the Ruby 3.5 deprecation warning.
  spec.add_dependency "ostruct", "~> 0.6"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
