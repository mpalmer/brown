# A single stimulus group in a Brown Agent.
#
# This is all the behind-the-scenes plumbing that's required to make the
# trickiness of stimuli work correctly.  In general, if you're a Brown user
# and you ever need to do anything with anything in here, something has gone
# terribly, terribly wrong somewhere.
#
class Brown::Agent::Stimulus
	# The name of the method to call when the stimulus is triggered.
	#
	# @return [String]
	#
	attr_reader :method_name
	
	# The chunk of code to call over and over again to listen for the stimulus.
	#
	# @return [Proc]
	#
	attr_reader :stimuli_proc

	# The class to instantiate to process a stimulus.
	#
	# @return [Class]
	#
	attr_reader :agent_class

	# Create a new stimulus.
	#
	# @param method_name [String] The method to call on an instance of
	#   `agent_class` to process a single stimulus event.
	#
	# @param stimuli_proc [Proc] What to call over and over again to listen
	#   for new stimulus events.
	#
	# @param agent_class [Class] The class to instantiate when processing
	#   stimulus events.
	#
	# @param logger [Logger] Where to log things to for this stimulus.
	#   If left as the default, no logging will be done.
	#
	def initialize(method_name:, stimuli_proc:, agent_class:, logger: Logger.new("/dev/null"))
		@method_name  = method_name
		@stimuli_proc = stimuli_proc
		@agent_class  = agent_class
		@thread_group = ThreadGroup.new
		@logger       = logger
	end

	# Fire off the stimulus listener.
	#
	# @param once [Symbol, NilClass] Ordinarily, when the stimulus is run, it
	#   just keeps going forever (or until stopped, at least).  If you just
	#   want to run the stimulus listener proc once, and then return, you can
	#   pass the special symbol `:once` here.
	#
	def run(once = nil)
		if once == :once
			stimuli_proc.call(->(*args) { process(*args) })
		else
			@runner_thread = Thread.current
			begin
				while @runner_thread
					begin
						stimuli_proc.call(method(:spawn_worker))
					rescue Brown::StopSignal, Brown::FinishSignal
						raise
					rescue Exception => ex
						log_failure("Stimuli listener", ex)
					end
				end
			rescue Brown::StopSignal
				stop
			rescue Brown::FinishSignal
				finish
			rescue Exception => ex
				log_failure("Stimuli runner", ex)
			end
		end
	end

	# Signal the stimulus to immediately shut down everything.
	#
	# This will cause all stimulus processing threads to be terminated
	# immediately.  You probably want to use {#finish} instead, normally.
	#
	def stop
		@thread_group.list.each do |th|
			th.raise Brown::StopSignal.new("stimulus thread_group")
		end

		finish
	end

	# Stop the stimulus listener, and wait gracefull for all currently
	# in-progress stimuli processing to finish before returning.
	#
	def finish
		if @runner_thread and @runner_thread != Thread.current
			@runner_thread.raise(Brown::StopSignal.new("stimulus loop"))
		end
		@runner_thread = nil

		@thread_group.list.each { |th| th.join }
	end

	private

	# Process a single stimulus event.
	#
	def process(*args)
		instance = agent_class.new

		if instance.method(method_name).arity == 0
			instance.__send__(method_name)
		else
			instance.__send__(method_name, *args)
		end
	end

	# Fire off a new thread to process a single stimulus event.
	#
	def spawn_worker(*args)
		@thread_group.add(
			Thread.new(args) do |args|
				begin
					process(*args)
				rescue Brown::StopSignal, Brown::FinishSignal
					# We're OK with this; the thread will now
					# quietly die.
				rescue Exception => ex
					log_failure("Stimulus worker", ex)
				end
			end
		)
	end

	# Standard log formatting for caught exceptions.
	#
	def log_failure(what, ex)
		@logger.error { "#{what} failed: #{ex.message} (#{ex.class})" }
		@logger.info  { ex.backtrace.map { |l| "    #{l}" }.join("\n") }
	end
end
