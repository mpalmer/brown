begin
	require 'git-version-bump'
rescue LoadError
	nil
end

Gem::Specification.new do |s|
	s.name = "brown"

	s.version = GVB.version rescue "0.0.0.1.NOGVB"
	s.date =    GVB.date    rescue Time.now.strftime("%Y-%m-%d")

	s.platform = Gem::Platform::RUBY

	s.summary  = "Autonomous agent framework"

	s.authors  = ["Matt Palmer"]
	s.email    = ["theshed+brown@hezmatt.org"]
	s.homepage = "http://theshed.hezmatt.org/brown"

	s.files = `git ls-files -z`.split("\0").reject { |f| f =~ /^(G|spec|Rakefile)/ }
	s.executables = %w{brown}

	s.required_ruby_version = ">= 2.1.0"

	s.add_runtime_dependency "bunny", "~> 1.7"
  s.add_runtime_dependency "service_skeleton", ">= 0.0.0.41.g9507cda"

	s.add_development_dependency 'bundler'
  s.add_development_dependency 'git-version-bump'
	s.add_development_dependency 'github-release'
	s.add_development_dependency 'guard-rspec'
	s.add_development_dependency 'pry-byebug'
	s.add_development_dependency 'rake', '>= 10.4.2'
	# Needed for guard
	s.add_development_dependency 'rb-inotify', '~> 0.9'
	s.add_development_dependency 'redcarpet'
	s.add_development_dependency 'rspec'
	s.add_development_dependency 'yard'
end
