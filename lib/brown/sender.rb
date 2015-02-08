# -*- encoding: utf-8 -*-

require 'brown/logger'
require 'brown/util'

class Brown::Sender
	include Brown::Logger
	include Brown::Util

	attr_reader :name

	def initialize(queue_def, opts={})
		@queue_def = queue_def.is_a?(Brown::QueueDefinition) ? queue_def : Brown::QueueDefinition.new(queue_def, opts)
		@name      = @queue_def.denormalise

		@reply_container = {}

		@message_count = 0

		@channel_completion = EM::Completion.new

		open_channel do |channel|
			logger.debug { "Opening a channel for sending" }
			@channel_completion.succeed(channel)
		end
	end

	def publish(payload, opts={}, &blk)
		logger.debug { "Publishing to: [queue]: #{@queue_def.denormalise}. [options]: #{opts}" }
		logger.debug { "ACL content: [queue]: #{@queue_def.denormalise}, [metadata type]: #{payload.class}, [message]: #{payload.inspect}" }

		increment_counter

		type = Brown::ACLLookup.get_by_type(payload.class)

		@channel_completion.completion do |channel|
			logger.debug { "Publishing #{payload.inspect} to queue #{@queue_def.denormalise}" }
			AMQP::Exchange.default(channel).publish(payload.to_s, opts.merge(:type => type, :routing_key => @queue_def.normalise), &blk)
		end
	end

	def delete(&blk)
		queue.delete do
			@channel_completion.completion do |channel|
				channel.close(&blk)
			end
		end
	end

=begin
	def status(&blk)
		@queue_completion.completion do |queue|
			queue.status do |num_messages, num_consumers|
				blk.call(num_messages, num_consumers) if blk
			end
		end
	end

	def message_count(&blk)
		status do |messages|
			blk.call(messages) if blk
		end
	end

	def consumer_count(&blk)
		status do |_, consumers|
			blk.call(consumers) if blk
		end
	end
=end

	def counter
		@message_count
	end

	# Define a channel error handler.
	def on_error(chain=false, &blk)
		@channel_completion.completion do |channel|
			channel.on_error(&blk)
		end
	end

	def queue_name
		@queue_def.denormalise
	end

	private

	def increment_counter(value=1)
		@message_count += value
	end
end
