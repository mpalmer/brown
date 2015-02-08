# -*- encoding: utf-8 -*-

require "brown/amqp_errors"
require "brown/logger"

module Brown::Util
	include Brown::AmqpErrors
	include Brown::Logger

	def number_of_messages
		status do |num_messages, _|
			yield num_messages
		end
	end

	def number_of_consumers
		status do |_, num_consumers|
			yield num_consumers
		end
	end

	private

	def open_channel(opts={}, &blk)
		AMQP::Channel.new(Brown.connection) do |channel,_|
			logger.debug { "Opened channel: #{"%#x" % channel.object_id}" }

			channel.auto_recovery = true
			logger.debug { "Channel auto recovery enabled" }

			# Set up QoS. If you do not do this then any subscribes will get
			# overwhelmed if there are too many messages.
			prefetch = opts[:prefetch] || 1

			channel.prefetch(prefetch)
			logger.debug { "AMQP prefetch set to: #{prefetch}" }

			blk.call(channel)
		end
	end

	def random(prefix = '', suffix = '')
		"#{prefix}#{SecureRandom.hex(8)}#{suffix}"
	end

	def option_or_default(options, key, default, &blk)
		if options.is_a?(Hash)
			if options.key?(key)
				v = options.delete(key)
				(blk) ? blk.call(v) : v
			else
				default
			end
		else
			raise ArguementError, "Options must be a Hash."
		end
	end
end
