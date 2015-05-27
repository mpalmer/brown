require 'brown'
require 'brown/agent/amqp_message_mock'

# Additional testing methods for {Brown::Agent}.
#
# You can cause these methods to become part of {Brown::Agent} with
#
#     require 'brown/test_helpers'
#
module Brown::TestHelpers
	#:nodoc:
	def self.included(base)
		base.class_eval do
			%i{memo amqp_publisher amqp_listener}.each do |m|
				alias_method "#{m}_without_test".to_sym, m
				alias_method m, "#{m}_with_test".to_sym
			end
		end
	end

	# Is there not an arbitrary stimulus with the specified name registered
	# on this agent?
	#
	# @param name [Symbol]
	#
	# @return Boolean
	#
	def stimulus?(name)
		@stimuli && @stimuli.has_key?(name)
	end

	# Is there a memo with the specified name registered on this agent?
	#
	# @param name [Symbol]
	#
	# @return Boolean
	#
	def memo?(name)
		@memos && @memos.has_key?(name)
	end

	#:nodoc:
	#
	# Test-specific decorator to replace the "real" memo container object
	# with a test-enabled alternative.
	#
	def memo_with_test(name, safe=false, &generator)
		memo_without_test(name, safe, &generator)

		# Throw out the real memo, replace with our own testing-enabled variant
		@memos[name] = Brown::Agent::Memo.new(generator, safe, true)
	end

	# Is there a timer which will go off every `n` seconds registered on this
	# agent?
	#
	# @param n [Integer]
	#
	# @return Boolean
	#
	def timer?(n)
		!instance_methods.select { |m| m =~ /^every_#{n}__/ }.empty?
	end

	# Set off all timers which trigger every `n` seconds on the running agent.
	#
	# @param n [Integer]
	#
	def trigger(n)
		self.instance_methods.select { |m| m =~ /^every_#{n}__/ }.each do |m|
			self.new.__send__(m)
		end
	end

	#:nodoc:
	#
	# Test-specific decorator to record the existence of a publisher.
	#
	def amqp_publisher_with_test(name, *args)
		@amqp_publishers ||= {}

		@amqp_publishers[name] = true

		amqp_publisher_without_test(name, *args)
	end

	# Is there a publisher with the specified name registered on this agent?
	#
	# @param name [Symbol]
	#
	# @return Boolean
	#
	def amqp_publisher?(name)
		@amqp_publishers && @amqp_publishers[name]
	end

	#:nodoc:
	#
	# Test-specific decorator to record the details of a listener.
	#
	def amqp_listener_with_test(exchange_name, *args, &blk)
		@amqp_listeners ||= {}

		@amqp_listeners[exchange_name.to_s] = blk

		amqp_listener_without_test(exchange_name, *args, &blk)
	end

	# Is there a listener on the specified exchange name registered on this agent?
	#
	# @param exchange_name [#to_s]
	#
	# @return Boolean
	#
	def amqp_listener?(exchange_name)
		@amqp_listeners && @amqp_listeners[exchange_name.to_s].is_a?(Proc)
	end

	# Cause a message to be received by the listener on `exchange_name`.
	#
	# @param exchange_name [#to_s] the name of the exchange.
	#
	# @param payload [String] the literal string which is the payload of the
	#   message.
	#
	# @return [Boolean] whether or not the message was acked.  You *usually*
	#   want to check that this is true, because an agent that doesn't ack
	#   each message when it has finished processing it is almost always
	#   buggy, but there are specialised circumstances where you actually
	#   want to *not* ack the message.
	#
	# @raise [ArgumentError] if you attempt to send a message via an exchange
	#   that isn't being listened on.
	#
	def amqp_receive(exchange_name, payload, **opts)
		unless amqp_listener?(exchange_name)
			raise ArgumentError,
			      "Unknown exchange: #{exchange_name}"
		end

		msg = Brown::Agent::AMQPMessageMock.new(opts.merge(payload: payload))

		@amqp_listeners[exchange_name].call(msg)

		msg.acked?
	end
end

class << Brown::Agent
	include Brown::TestHelpers
end

