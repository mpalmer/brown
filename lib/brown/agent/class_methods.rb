require 'logger'
require 'securerandom'

module Brown::Agent::ClassMethods
	# The available stimuli.
	#
	# @return [Array<Hash<Symbol, Object>>]
	#
	attr_reader :stimuli

	# The available memos.
	#
	# @return [Array<Hash<Symbol, Object>>]
	#
	attr_reader :memos

	# Define a generic stimulus for this agent.
	#
	# This is a fairly low-level method, designed to provide a means for
	# defining stimuli for which there isn't a higher-level, more-specific
	# stimulus definition approach.
	#
	# When the agent is started (see {.run}), the block you provide will be
	# executed in a dedicated thread.  Every time the block finishes, it will be
	# run again.  Your block should do whatever it needs to do to detect when a
	# stimuli is available (preferably by blocking somehow, rather than polling,
	# because polling sucks).  When your code detects that a stimulus has been
	# received, it should run `worker.call`, passing in any arguments that are
	# required to process the stimulus.  That will then spawn a new thread and
	# call the specified `method_name` on the agent object, passing in the
	# arguments that were passed to `worker.call`.
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
	def stimulate(method_name, stimulus_name, &blk)
		@stimuli ||= []

		@stimuli << {
			name: stimulus_name,
			method_name:  method_name,
			stimuli_proc: blk,
		}
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
	# Because we do everything in threads, and because dealing with locking by
	# hand is a nightmare, access to memos is protected by a mutex.  This means
	# that any time you want to do something with a memo, you call its name and
	# pass a block to do whatever you want to do with the value, like this:
	#
	#     config { |cfg| puts "foo is #{cfg[:foo]}" }
	#
	# Now, you can, if you want, "leak" this object out of the mutex, with
	# various sorts of assignment.  DO NOT SUCCUMB TO THIS TEMPTATION.  If
	# you do this, you will risk all sorts of concurrency bugs, where two
	# threads try to read and/or manipulate the object at the same time
	# and all hell breaks loose.
	#
	# Note that there is intentionally no way to reassign a memo object.
	# This doesn't mean that memo objects are "read-only", however.  The
	# state of the object can be mutated by calling any method on the
	# object that modifies it.  If you want more read-only(ish) memos, you
	# probably want to call `#freeze` on your object when you create it
	# (although all the usual caveats about the many limitations of `#freeze`
	# still apply).
	#
	# @param name [Symbol] the name of the memo, and hence the name of the
	#   method that should be called to retrieve the memo's value.
	#
	# @return void
	#
	def memo(name, &generator)
		define_method(name) do |&blk|
			raise RuntimeError, "Memo values are only available inside a block" unless blk

			@memo_mutexes_mutex.synchronize do
				@memo_mutexes[name] ||= Mutex.new
			end

			@memo_mutexes[name].synchronize do
				@memo_values[name] ||= instance_eval(&generator)
				blk.call(@memo_values[name])
			end
		end
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
	# @param desc [#to_s] a descriptive name to use for the trigger in
	#   metrics and the suchlike.  If you define two stimuli with the same
	#   periodicity, you *must* give them different descriptions.
	#
	# @yield every `n` seconds.
	#
	def every(n, desc = "every_#{n}", &blk)
		method_name = desc.to_sym
		define_method(method_name, &blk)

		stimulate(method_name, desc) { |worker| Kernel.sleep n; worker.call }
	end

	# Keep a block of code running, calling it again whenever it exits.
	#
	# @param desc [#to_s] a descriptive name to use for the trigger.
	#   Each `respawn` block must have its own description.
	#
	# @yield every time the code block finishes.
	#
	def respawn(desc, &blk)
		mutex   = Mutex.new
		cv      = ConditionVariable.new
		running = false

		method_name = desc.to_sym
		define_method(method_name) do
			mutex.synchronize do
				begin
					instance_eval(&blk)
				ensure
					running = false
					cv.signal
				end
			end
		end

		stimulate(method_name, desc) do |worker|
			mutex.synchronize do
				while running
					cv.wait(mutex)
				end
				running = true
				worker.call
			end
		end
	end
end

Brown::Agent.extend(Brown::Agent::ClassMethods)
