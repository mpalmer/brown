# -*- encoding: utf-8 -*-

require 'brown/logger'

class Brown::Message
	include Brown::Logger

	attr_reader :payload, :metadata

	def initialize(payload, metadata, requeue_queue, requeue_options, opts = {}, &blk)
		@metadata = metadata

		@requeue_queue   = requeue_queue
		@requeue_options = requeue_options

		@requeue_options[:strategy] ||= :linear

		@requeue_options[:on_requeue] ||= ->(count, total_count, cumulative_delay) {
			logger.info { "Requeuing (#{@requeue_options[:strategy]}) message on queue: #{@requeue_queue.name}, count: #{count} of #{total_count}." }
		}

		@requeue_options[:on_requeue_limit] ||= ->(message, count, total_count, cumulative_delay) {
			logger.info { "Not attempting any more requeues, requeue limit reached: #{total_count} for queue: #{@requeue_queue.name}, cummulative delay: #{cumulative_delay}s." }
		}

		klass = Brown::ACLLookup.get_by_hash(metadata.type)
		raise RuntimeError, "Unknown ACL: #{metadata.type}" if klass.nil?

		@payload = klass.new.parse_from_string(payload)

		blk.call(@payload, self)
		ack if opts[:auto_ack]
	end

	def ack(multiple = false)
		@metadata.ack(multiple)
	end

	def nak(opts = {})
		@metadata.reject(opts)
	end

	alias_method :reject, :nak

	def requeue
		if current_requeue_number < @requeue_options[:count]
			cumulative_delay = case @requeue_options[:strategy].to_sym
			when :linear
				@requeue_options[:delay] * (current_requeue_number + 1)
			when :exponential
				@requeue_options[:delay] * (2 ** current_requeue_number)
			when :exponential_no_initial_delay
				@requeue_options[:delay] * (2 ** current_requeue_number - 1)
			else
				raise RuntimeError, "Unknown requeue strategy #{@requeue_options[:strategy].to_sym.inspect}"
			end

			EM.add_timer(cumulative_delay) do
				new_headers = (@metadata.headers || {}).merge('requeue' => current_requeue_number + 1)
				@requeue_queue.publish(@payload, @metadata.to_hash.merge(:headers => new_headers))
			end

			@requeue_options[:on_requeue].call(current_requeue_number + 1, @requeue_options[:count], cumulative_delay)
		else
			@requeue_options[:on_requeue_limit].call(@payload, current_requeue_number + 1, @requeue_options[:count], @requeue_options[:delay] * current_requeue_number)
		end
	end

	private
	def current_requeue_number
		(@metadata.headers['requeue'] rescue nil) || 0
	end
end
