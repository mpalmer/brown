require 'brown'
require 'brown/agent/amqp_message_mock'

# Additional testing methods for {Brown::Agent}.
#
# You can cause these methods to become part of {Brown::Agent} with
#
#     require 'brown/test'
#
module Brown::TestHelpers
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
	def memo(name, safe=false, &generator)
		super

		# Throw out the real memo, replace with our own testing-enabled variant
		@memos[name] = Brown::Agent::Memo.new(generator, safe, true)
	end

	# Reset all memos to "undefined" values.
	#
	# Because memo values are cached at the class level, this means that they're
	# cached between test cases.  Often, this isn't what you want (because if the
	# value of the memo was changed by a test case, the next test won't run in a
	# pristine environment).  Calling this method will cause all of the memos in
	# the agent to be reset to a state which is the same as if the memo had never
	# been called at all.
	#
	def reset_memos
		@memos ||= {}

		@memos.values.each do |memo|
			memo.instance_variable_set(:@cached_value, nil)
		end
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
		trigger_methods = self.instance_methods.select { |m| m =~ /^every_#{n}__/ }

		if trigger_methods.empty?
			raise RuntimeError,
			      "Nothing is set to run every #{n} second#{n == 1 ? "" : "s"}"
		end

		trigger_methods.each do |m|
			self.new.__send__(m)
		end
	end

	#:nodoc:
	#
	# Test-specific decorator to record the existence of a publisher.
	#
	def amqp_publisher(name, *args)
		@amqp_publishers ||= {}

		@amqp_publishers[name] = true

		publisher =
		self.define_singleton_method

		super
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
	def amqp_listener(exchange_name, *args, &blk)
		@amqp_listeners ||= {}

		if exchange_name.is_a? Array
			exchange_name.each do |en|
				@amqp_listeners[en.to_s] = blk
			end
		else
			@amqp_listeners[exchange_name.to_s] = blk
		end

		super
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
		msg = Brown::Agent::AMQPMessageMock.new(opts.merge(payload: payload))

		(self.class.amqp_listeners || []).each do |listener|
			if listener[:exchange_list].include?(exchange_name.to_s)
				m = SecureRandom.uuid
				define_singleton_method(m.to_sym, &listener[:callback])
				__send__(m.to_sym, msg)
			end
		end

		msg.acked?
	end
end

Brown::Agent.prepend(Brown::TestHelpers)
