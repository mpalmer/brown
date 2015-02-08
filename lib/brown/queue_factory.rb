# -*- encoding: utf-8 -*-

class Brown::QueueFactory
	def initialize
		@cache = {}
	end

	# Convenience method that returns a Sender object.
	def sender(queue_name, opts={}, &blk)
		k = "sender:#{queue_name}"
		@cache[k] ||= Brown::Sender.new(queue_name, opts)
		blk.call(@cache[k])
	end

	# Convenience method that returns a Receiver object.
	def receiver(queue_name, opts={}, &blk)
		k = "receiver:#{queue_name}"
		@cache[k] ||= Brown::Receiver.new(queue_name, opts)
		blk.call(@cache[k])
	end

	# Passes each queue to the supplied block.
	def each_queue
		@cache.values.each do |queue|
			yield queue if block_given?
		end
	end

	# Returns all queues as a hash, with the queue name being the key.
	def queues
		@cache
	end
end
