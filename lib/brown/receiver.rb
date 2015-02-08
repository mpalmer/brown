# -*- encoding: utf-8 -*-

require 'brown/logger'
require 'brown/util'

class Brown::Receiver
	include Brown::Logger
	include Brown::Util

	def initialize(queue_def, opts={}, &blk)
		@queue_def = queue_def.is_a?(Brown::QueueDefinition) ? queue_def : Brown::QueueDefinition.new(queue_def, opts)

		@acl_type_cache = Brown::ACLLookup

		@options = opts

		@requeue_options = {}
		@requeue_queue   = Brown::Sender.new(@queue_def, opts)

		@payload_type = Array(option_or_default(@queue_def.options, :type, []))

		prefetch = option_or_default(@queue_def.options, :prefetch, 1)

		@channel_completion = EM::Completion.new
		@queue_completion = EM::Completion.new

		open_channel(:prefetch => prefetch) do |channel|
			logger.debug { "channel open for receiver on #{@queue_def.denormalise}" }
			channel.on_error do |ch, close|
				logger.fatal { "Channel error: #{close.inspect}" }
			end

			channel.queue(@queue_def.normalise) do |queue|
				logger.debug { "Registered queue #{@queue_def.denormalise} on channel" }
				@queue_completion.succeed(queue)
			end

			@channel_completion.succeed(channel)
		end

		blk.call(self) if blk
	end

	def ack(multiple=false)
		@channel_completion.completion {|channel| channel.ack(multiple) }
	end

	# Subscribes to a queue and passes the headers and payload into the
	# block. +subscribe+ will automatically acknowledge the message unless
	# the options sets :ack to false.
	def subscribe(opts = {}, &blk)
		@queue_completion.completion do |queue|
			logger.debug { "Subscribing to: [queue]:#{@queue_def.denormalise} [options]:#{@queue_def.options}" }
			queue.subscribe(opts.merge(:ack => true)) do |metadata,payload|
				logger.debug { "Received a message on #{@queue_def.denormalise}: #{metadata.to_hash.inspect}" }
				if payload
					on_message(metadata, payload, &blk)
				else
					logger.debug { "Received null message on: #{@queue_def.denormalise} [options]:#{@queue_def.options}" }
				end
			end
		end
	end

	def unsubscribe(&blk)
		@queue_completion.completion do |queue|
			queue.unsubscribe(&blk)
		end
	end

	def requeue_parameters(opts)
		@requeue_options.merge!(opts)
	end

	def on_requeue(&blk)
		@requeue_options[:on_requeue] = blk
	end

	def on_requeue_limit(&blk)
		@requeue_options[:on_requeue_limit] = blk
	end

	# pops a message off the queue and passes the headers and payload
	# into the block. +pop+ will automatically acknowledge the message
	# unless the options sets :ack to false.
	def pop(&blk)
		@queue_completion.completion do |queue|
			queue.pop({}) do |metadata, payload|
				if payload
					on_message(metadata, payload, &blk)
				else
					blk.call(nil,nil)
				end
			end
		end
	end

	# Define a channel error handler.
	def on_error(chain=false, &blk)
		# TODO Check that this chains callbacks
		@channel_completion.completion do |channel|
			channel.on_error(&blk)
		end
	end

	def queue_name
		@queue_def.denormalise
	end

	def delete(&blk)
		@queue_completion.completion do |queue|
			@channel_completion.completion do |channel|
				queue.unbind(exchange) do
					queue.delete do
						exchange.delete do
							channel.close(&blk)
						end
					end
				end
			end
		end
	end

	def status(&blk)
		@queue_completion.completion do |queue|
			queue.status do |num_messages, num_consumers|
				blk.call(num_messages, num_consumers)
			end
		end
	end

	private

	def on_message(metadata, payload, &blk)
		if @payload_type.empty? || @payload_type.include?(@acl_type_cache.get_by_hash(metadata.type))
			Brown::Message.new(payload, metadata, @requeue_queue, @requeue_options, @options, &blk)
		else
			allowable_acls = @payload_type.join(", ")
			received_acl = @acl_type_cache.get_by_hash(metadata.type)
			raise ACL::IncorrectTypeError, "Received ACL: #{received_acl} on queue: #{@queue_def.denormalise}. This queue can only accept the following ACLs: #{allowable_acls}"
		end
	end
end
