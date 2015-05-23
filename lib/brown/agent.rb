require 'logger'
require 'securerandom'

# A Brown Agent.  The whole reason we're here.
#
# An agent is the fundamental unit of work in the Brown universe.  Pretty
# much everything you do to an agent is done on its class; the individual
# instances of the agent are run by the agent, internally, when reacting to
# stimuli.
#
class Brown::Agent
	class << self
		# Define a generic stimulus for this agent.
		#
		# This is a fairly low-level method, designed to provide a means for
		# defining stimuli for which there isn't a higher-level, more-specific
		# stimulus definition approach.
		#
		# When the agent is started (see {.run}), the block you provide will
		# be executed in a dedicated thread.  Every time the block finishes,
		# it will be run again.  Your block should do whatever it needs to do
		# to detect when a stimuli is available (preferably by blocking
		# somehow, rather than polling, because polling sucks).  When your
		# code detects that a stimulus has been received, it should run
		# `worker.call`, passing in any arguments that are required to process
		# the stimulus.  That will then create a new instance of the agent
		# class, and call the specified `method_name` on that instance,
		# passing in the arguments that were passed to `worker.call`.
		#
		# @see .every
		#
		# @param method_name [Symbol] the name of the method to call when the
		#   stimulus is triggered.
		#
		# @yieldparam worker [Proc] call this when you want a stimulus
		#   processed, passing in anything that the stimulus processing method
		#   (as specified by `method_name`) needs to do its job.
		#
		def stimulate(method_name, &blk)
			@stimuli ||= []

			@stimuli << Brown::Agent::Stimulus.new(
							  method_name:  method_name,
							  stimuli_proc: blk,
							  agent_class:  self,
							  logger:       logger
							)
		end

		# Define a "memo" for this agent.
		#
		# A "memo" is an object which is common across all instances of a
		# particular agent, and which is (usually) local to that agent.  The
		# intended purpose is for anything that is needed for processing
		# stimuli, but which you don't want to recreate for every stimuli. 
		# Examples of this sort of thing include connection pools (database,
		# HTTP connections, etc), config files, and caches.  Basically,
		# anything that has a non-trivial setup time, or which you *want* to
		# share across all stimuli processing, should go in a memo.
		#
		# Because we do everything in threads, and because dealing with
		# locking by hand is a nightmare, access to memos is, by default,
		# protected by a mutex.  This means that any time you want to do
		# something with a memo, you call its name and pass a block to do
		# whatever you want to do with the value, like this:
		#
		#     config { |cfg| puts "foo is #{cfg[:foo]}" }
		#
		# Now, you can, if you want, "leak" this object out of the mutex, with
		# various sorts of assignment.  DO NOT SUCCUMB TO THIS TEMPTATION.  If
		# you do this, you will risk all sorts of concurrency bugs, where two
		# threads try to read and/or manipulate the object at the same time
		# and all hell breaks loose.
		#
		# If, *and only if*, you are **100% confident** that the
		# object you want to work with is, in fact, entirely thread-safe (the
		# documentation should mention this), then you can mark a memo object
		# as "safe", either by passing `true` to {.memo}, or using the handy-dandy
		# {.safe_memo} method.  In this case, you can just reference the memo
		# name wherever you like:
		#
		#     safe_memo :db do
		#       Sequel.connect("postgres:///app_database")
		#     end
		#
		#     #...
		#     db[:foo].where { :baz > 42 }
		#
		# Note that there is intentionally no way to reassign a memo object. 
		# This doesn't mean that memo objects are "read-only", however.  The
		# state of the object can be mutated by calling any method on the
		# object that modifies it.  If you want more read-only(ish) memos, you
		# probably want to call `#freeze` on your object when you create it
		# (although all the usual caveats about `#freeze` still apply).
		#
		# @see .safe_memo
		#
		# @param name [Symbol] the name of the memo, and hence the name of the
		#   method that should be called to retrieve the memo's value.
		#
		# @param safe [Boolean] whether or not the object will be "safe" for
		#   concurrent access by multiple threads.  Do *not* enable this
		#   unless you are completely sure.
		#
		# @return void
		#
		def memo(name, safe=false, &generator)
			name = name.to_sym
			@memos ||= {}
			@memos[name] = Brown::Agent::Memo.new(generator, safe)

			define_method(name) do |&blk|
				self.class.__send__(name, &blk)
			end

			self.singleton_class.__send__(:define_method, name) do |&blk|
				memos[name].value(&blk)
			end
		end

		# A variant of {.memo} which is intended for objects which are
		# inherently thread-safe within themselves.
		#
		# @see .memo
		#
		def safe_memo(name, &generator)
			memo(name, true, &generator)
		end

		# Execute a block of code periodically.
		#
		# This pretty much does what it says on the tin.  Every
		# `n` seconds (where `n` can be a float) the given block
		# of code is executed.
		#
		# Don't expect too much precision in the interval; we just sleep
		# between triggers, so there might be a bit of an extra delay between
		# invocations.
		#
		# @param n [Numeric] The amount of time which should elapse between
		#   invocations of the block.
		#
		# @yield every `n` seconds.
		#
		def every(n, &blk)
			method_name = ("every_#{n}__" + SecureRandom.uuid).to_sym
			define_method(method_name, &blk)

			stimulate(method_name) { |worker| sleep n; worker.call }
		end

		# Start the agent running.
		#
		# This fires off the stimuli listeners and then waits.  If you want to
		# do anything else while this runs, you'll want to fire this in a
		# separate thread.
		#
		def run
			begin
				@thread_group ||= ThreadGroup.new
				@runner_thread = Thread.current

				stimuli.each do |s|
					@thread_group.add(
						Thread.new(s) do |s|
							begin
								s.run
							rescue Brown::StopSignal
								# OK then
							end
						end
					)
				end

				@thread_group.list.each do |th|
					begin
						th.join
					rescue Brown::StopSignal
						# OK then
					end
				end
			rescue Exception => ex
				logger.error { "Agent #{self} caught unhandled exception: #{ex.message} (#{ex.class})" }
				logger.info  { ex.backtrace.map { |l| "    #{l}" }.join("\n") }
				stop
			end
		end

		# Stop the agent running.
		#
		# This can either be called in a separate thread, or a signal handler, like
		# so:
		#
		#     Signal.trap("INT") { SomeAgent.stop }
		#
		#     agent.run
		#
		def stop
			@thread_group.list.each do |th|
				th.raise Brown::FinishSignal.new("agent finish")
			end

			@thread_group.list.each do |th|
				th.join
			end
		end

		# Set the logger that this agent will use to report problems.
		#
		# @param l [Logger]
		#
		def logger=(l)
			@logger = l
		end

		# Get or set the logger for this agent.
		#
		# @param l [Logger]
		#
		# @return [Logger]
		#
		def logger(l=nil)
			(@logger = (l || @logger)) || (self == Brown::Agent ? Logger.new($stderr) : Brown::Agent.logger)
		end

		private

		# The available stimuli.
		#
		# @return [Array<Brown::Agent::Stimulus>]
		#
		attr_reader :stimuli
		
		# The available memos.
		#
		# @return [Hash<Symbol, Brown::Agent::Memo>]
		#
		attr_reader :memos
	end
end
