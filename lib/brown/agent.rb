require "service_skeleton"

# A Brown Agent.  The whole reason we're here.
#
# An agent is the fundamental unit of work in the Brown universe.  Pretty much
# everything you configure on an agent is done on its class; the individual
# instances of the agent are spawned by the agent's stimuli, internally.
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
				Brown::Agent::Stimulus.new(method: self.method(s[:method_name]), stimuli_proc: s[:stimuli_proc], logger: logger).tap do |stimulus|
					stimulus.start!
				end
			end

			@running = true

			while @running
				@op_cv.wait(@op_mutex)
			end
		end
	end

	private

	def shutdown
		@op_mutex.synchronize do
			return unless @running
			until @stimuli_workers.empty? do
				@stimuli_workers.pop.stop!
			end
			@running = false
			@op_cv.signal
		end
	end
end

require_relative "./agent/class_methods"
