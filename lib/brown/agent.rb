# -*- encoding: utf-8 -*-

require "brown/logger"

class Brown::Agent
	include Brown::Logger

	# Override this method to implement your own agent.
	def run
		raise ArgumentError, "You must override this method"
	end

	def receiver(queue_name, opts={}, &blk)
		queues.receiver(queue_name, opts, &blk)
	end

	def sender(queue_name, opts={}, &blk)
		queues.sender(queue_name, opts, &blk)
	end

	class << self
		# I care not for your opts... this is just here for Smith compatibility
		def options(opts)
		end
	end

	protected

	def queues
		@queues ||= Brown::QueueFactory.new
	end
end
