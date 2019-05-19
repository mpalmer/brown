require "service_skeleton"

# A Brown Agent.  The whole reason we're here.
#
class Brown::Agent < ServiceSkeleton
	def initialize(*_)
		super

		@memo_values  = {}
		@memo_mutexes = {}
		@memo_mutexes_mutex = Mutex.new

		@op_mutex = Mutex.new
		@op_cv    = ConditionVariable.new
	end

	def run
		@op_mutex.synchronize do
			@stimuli_workers = ((self.class.stimuli || []) + (@stimuli || [])).map do |s|
				if s[:method_name]
					s[:method] = self.method(s[:method_name])
				end
				stimulus_metrics = Stimulus::Metrics.new(:"#{self.service_name}_#{s[:name]}", registry: self.metrics)
				logger.debug(logloc) { "Starting stimulus #{s[:name]}" }
				Brown::Agent::Stimulus.new(method: s[:method], stimuli_proc: s[:stimuli_proc], logger: logger, metrics: stimulus_metrics).tap do |stimulus|
					stimulus.start!
					logger.debug(logloc) { "Stimulus started" }
				end
			end

			@running = true

			while @running
				logger.debug(logloc) { "Agent runner taking a snooze" }
				@op_cv.wait(@op_mutex)
			end
		end
	end

	private

	def shutdown
		logger.debug(logloc) { "Shutdown requested" }
		@op_mutex.synchronize do
			logger.debug(logloc) { "Shutdown starting" }
			return unless @running
			logger.debug(logloc) { "Stopping #{@stimuli_workers.length} stimulus workers" }
			until @stimuli_workers.empty? do
				@stimuli_workers.pop.stop!
				logger.debug(logloc) { "One down, #{@stimuli_workers.length} to go" }
			end
			@running = false
			logger.debug(logloc) { "Signalling for pickup" }
			@op_cv.signal
		end
		logger.debug(logloc) { "Shutdown complete" }
	end
end

require_relative "./agent/class_methods"
