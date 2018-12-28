require "service_skeleton/background_worker"

# A single stimulus group in a Brown Agent.
#
# This is all the behind-the-scenes plumbing that's required to make the
# trickiness of stimuli work correctly.  In general, if you're a Brown user
# and you ever need to do anything with anything in here, something has gone
# terribly, terribly wrong somewhere.
#
class Brown::Agent::Stimulus
	include ServiceSkeleton::BackgroundWorker

	# The (bound) method to call when the stimulus is triggered.
	#
	# @return [String]
	#
	attr_reader :method

	# The chunk of code to call over and over again to listen for the stimulus.
	#
	# @return [Proc]
	#
	attr_reader :stimuli_proc

	# Create a new stimulus.
	#
	# @param method [String] The (bound) method to call to process a single
	#   stimulus event.
	#
	# @param stimuli_proc [Proc] What to call over and over again to collect
	#   the next stimulus event.
	#
	# @param logger [Logger] Where to log things to for this stimulus.
	#   If left as the default, no logging will be done.
	#
	def initialize(method:, stimuli_proc:, logger: Logger.new("/dev/null"))
		@method       = method
		@stimuli_proc = stimuli_proc
		@threads      = ThreadGroup.new
		@logger       = logger

		super
	end

	def start
		loop { run }
	end

	# Run the stimulus listener.
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
			@running = true
			begin
				while @running
					begin
						stimuli_proc.call(->(*args) { spawn_worker(*args) })
					rescue StandardError => ex
						log_exception(ex) { "Stimuli listener proc raised exception" }
					end
				end
			rescue ServiceSkeleton::BackgroundWorker.const_get(:TerminateBackgroundThread) => ex
				@threads.list.each { |th| th.raise(ex.class) }
				raise
			rescue StandardError => ex
				log_exception(ex) { "Mysterious exception while running stimulus listener for #{method.name}" }
			end
		end
	end

	# Gracefully stop all stimuli workers.
	#
	def shutdown
		logger.info(progname) { "shutting down" }
		@running = false

		logger.debug(progname) { "waiting for #{@threads.list.length} stimuli workers to finish" } unless @threads.list.empty?

		until @threads.list.empty? do
			@threads.list.first.join
		end

		logger.info(progname) { "shutdown complete." }
	end

	private

	attr_reader :logger

	def progname
		@progname ||= "StimulusWorker->#{method.name}"
	end

	# Process a single stimulus event.
	#
	def process(*args)
		logger.debug(progname) { "Processing stimulus.  Arguments: #{args.inspect}" }
		if method.arity == 0
			method.call
		else
			method.call(*args)
		end
	end

	# Fire off a new thread to process a single stimulus event.
	#
	def spawn_worker(*args)
		@threads.add(Thread.new(args) do |args|
			logger.debug(progname) { "Spawned new worker" }

			begin
				process(*args)
			rescue StandardError => ex
				log_exception(ex) { "Stimulus worker raised exception" }
			end
		end)
	end
end
