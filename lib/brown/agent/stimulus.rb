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
	# @param metrics [Brown::Agent::Stimulus::Metrics] Somewhere to record
	#   all the important numbers about the stimulus.
	#
	def initialize(method:, stimuli_proc:, logger: Logger.new("/dev/null"), metrics:)
		puts caller if method.nil?
		@method       = method
		@stimuli_proc = stimuli_proc
		@threads      = ThreadGroup.new
		@logger       = logger
		@metrics      = metrics

		super
	end

	def start
		@running = true

		while @running
			run
		end
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
			@metrics.last_trigger.set({}, Time.now.to_f)
			@metrics.processing_ruler.measure do
				stimuli_proc.call(->(*args) { process(*args) })
			end
		else
			@running = true
			logger.debug(logloc) { "Running stimulus listener for stimulus proc at #{@method.source_location.join(":")}" }
			Thread.handle_interrupt(Exception => :never) do
				begin
					while @running
						begin
							logger.debug(logloc) { "Calling stimulus_proc" }
							Thread.handle_interrupt(Exception => :immediate) do
								@metrics.last_trigger.set({}, Time.now.to_f)
								@metrics.processing_ruler.measure do
									stimuli_proc.call(->(*args) { spawn_worker(*args) })
								end
							end
						rescue StandardError => ex
							log_exception(ex) { "Stimuli listener proc raised exception" }
							sleep 1
						end
					end
				rescue ServiceSkeleton::BackgroundWorker.const_get(:TerminateBackgroundThread) => ex
					@threads.list.each { |th| th.raise(ex.class) }
					raise unless Thread.current == @bg_worker_thread
				rescue StandardError => ex
					log_exception(ex) { "Mysterious exception while running stimulus listener for #{method.name}" }
				end
			end
		end
	end

	# Gracefully stop all stimuli workers.
	#
	def shutdown
		logger.info(progname) { "shutting down" }
		@running = false

		logger.debug(progname) { "waiting for #{@threads.list.length} stimuli worker(s) to finish" }

		until @threads.list.empty? do
			@threads.list.first.join
		end

		logger.debug(progname) { "terminating stimulus listener" }
		super

		logger.info(progname) { "shutdown complete." }
	end

	private

	attr_reader :logger

	def progname
		@progname ||= "StimulusWorker->#{method.name rescue nil}"
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
