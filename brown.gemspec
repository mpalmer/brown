require "git-version-bump"

Gem::Specification.new do |s|
	s.name    = "brown"
	s.version = GVB.version
	s.date    = GVB.date

	s.summary = "Run individual smith agents directly from the command line"

	s.licenses = ["GPL-3"]

	s.authors = ["Richard Heycock", "Matt Palmer"]

	s.files = `git ls-files -z`.split("\0")
	s.executables = %w{brown}

	s.has_rdoc = false

	s.add_runtime_dependency "amqp",            "~> 1.4"
	s.add_runtime_dependency "envied",          "~> 0.8"
	s.add_runtime_dependency "eventmachine-le", "~> 1.0"
	s.add_runtime_dependency "extlib",          "~> 0.9"
	s.add_runtime_dependency "murmurhash3",     "~> 0.1"
	s.add_runtime_dependency "protobuf",        "~> 3.0"

	s.add_development_dependency "bundler"
	s.add_development_dependency "git-version-bump", "~> 0.10"
	s.add_development_dependency "rake",             "~> 10.4", ">= 10.4.2"
end
