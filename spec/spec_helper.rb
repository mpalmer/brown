require 'bundler'
Bundler.setup(:default, :development)
require 'rspec/core'
require 'rspec/mocks'
require "sigdump/setup"

if RUBY_VERSION =~ /^1\./
	require 'pry-debugger'
else
	require 'pry-byebug'
end

RSpec.configure do |config|
	config.fail_fast = true
#	config.full_backtrace = true

	config.expect_with :rspec do |c|
		c.syntax = :expect
	end
end

require_relative 'example_methods'
require_relative 'example_group_methods'

RSpec.configure do |config|
	config.order = :random

	config.include ExampleMethods
	config.extend  ExampleGroupMethods
end

require 'brown'
