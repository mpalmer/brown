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

			define_method(name) do |test=nil, &blk|
				self.class.__send__(name, test, &blk)
			end

			self.singleton_class.__send__(:define_method, name) do |test=nil, &blk|
				memos[name].value(test, &blk)
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

		# Declare an AMQP publisher, and create an AMQP exchange to publish to.
		#
		# On the assumption that you already know [how exchanges
		# work](http://www.rabbitmq.com/tutorials/amqp-concepts.html), I'll
		# just dive right in.
		#
		# This method creates an accessor method on your agent named after the
		# symbol you pass in as `name`, which returns an instance of
		# `Brown::Agent::AMQPPublisher`.  This object, in turn, defines an
		# AMQP exchange when it is created, and has a
		# `publish` method on it (see {Brown::Agent::AMQPPublisher#publish}) which
		# sends arbitrary messages to the exchange.
		#
		# @param name [Symbol] the name of the accessor method to call when
		#   you want to reference this publisher in your agent code.
		#
		# @param publisher_opts [Hash] options which are passed to
		#   {Brown::Agent::AMQPPublisher#initialize}.
		#
		# This method is a thin shim around {Brown::Agent::AMQPPublisher#initialize};
		# you should read that method's documentation for details of what
		# constitutes valid `publisher_opts`, and also what exceptions can be
		# raised.
		#
		# @see Brown::Agent::AMQPPublisher#initialize
		# @see Brown::Agent::AMQPPublisher#publish
		#
		def amqp_publisher(name, publisher_opts = {})
			opts = { :exchange_name => name }.merge(publisher_opts)

			safe_memo(name) { Brown::Agent::AMQPPublisher.new(opts) }
		end

		# Listen for messages from an AMQP broker.
		#
		# We setup a queue, bound to the exchange specified by the
		# `exchange_name` argument, and then proceed to hoover up all the
		# messages we can.
		#
		# The name of the queue that is created by default is derived from the
		# agent class name and the exchange name being bound to.  This allows
		# for multiple instances of the same agent, running in separate
		# processes or machines, to share the same queue of messages to
		# process, for throughput or redundancy reasons.
		#
		# @param exchange_name [#to_s] the name of the exchange to bind to.
		#
		# @param queue_name [#to_s] the name of the queue to create, if you
		#   don't want to use the class-derived default for some reason.
		#
		# @param amqp_url [#to_s] the URL of the AMQP broker to connect to.
		#
		# @param concurrency [Integer] how many messages to process in parallel.
		#   The default, `1`, means that a message will need to be acknowledged
		#   (by calling `message.ack`) in your worker `blk` before the broker
		#   will consider sending another.
		#
		#   If your agent is capable of processing more than one message in
		#   parallel (because the agent spends a lot of its time waiting for
		#   databases or HTTP requests, for example, or perhaps you're running
		#   your agents in a Ruby VM which has no GIL) you should increase
		#   this value to improve performance.  Alternately, if you want/need
		#   to batch processing (say, you insert 100 records into a database
		#   in a single query) you'll need to increase this to get multiple
		#   records at once.
		#
		#   Setting this to `0` is only for the adventurous.  It tells the
		#   broker to send your agent messages as fast as it can.  You still
		#   need to acknowledge the messages as you finish processing them
		#   (otherwise the broker will not consider them "delivered") but you
		#   will always be sent more messages if there are more to send, even
		#   if you never acknowledge any of them.  This *can* get you into an
		#   awful lot of trouble if you're not careful, so don't do it just
		#   because you can.
		#
		# @param blk [Proc] is called every time a message is received from
		#   the queue, and an instance of {Brown::Agent::AMQPMessage} will
		#   be passed as the sole argument.
		#
		# @yieldparam message [Brown::Agent::AMQPMessage] is passed to `blk`
		#   each time a message is received from the queue.
		#
		def amqp_listener(exchange_name = "",
		                  queue_name:  nil,
		                  amqp_url:    "amqp://localhost",
		                  concurrency: 1,
		                  &blk
		                 )
			listener_uuid = SecureRandom.uuid
			worker_method = "amqp_listener_worker_#{listener_uuid}".to_sym
			queue_memo    = "amqp_listener_queue_#{listener_uuid}".to_sym

			queue_name ||= self.name.to_s + (exchange_name.to_s == "" ? "" : "-#{exchange_name}")

			memo(queue_memo) do
				begin
					amqp = Bunny.new(amqp_url)
					amqp.start
				rescue Bunny::TCPConnectionFailed
					logger.error { "Failed to connect to #{amqp_url}" }
					sleep 5
					retry
				rescue Bunny::PossibleAuthenticationFailureError
					logger.error { "Authentication failure for #{amqp_url}" }
					sleep 5
					retry
				rescue StandardError => ex
					logger.error { "Unknown error while trying to connect to #{amqp_url}: #{ex.message} (#{ex.class})" }
					sleep 5
					retry
				end

				bind_queue(
				  amqp_session:  amqp,
				  queue_name:    queue_name,
				  exchange_name: exchange_name,
				  concurrency:   concurrency
				)
			end

			define_method(worker_method, &blk)

			stimulate(worker_method) do |worker|
				__send__(queue_memo) do |queue|
					queue.subscribe(manual_ack: true, block: true) do |di, prop, payload|
						yield Brown::Agent::AMQPMessage.new(di, prop, payload)
					end
				end
			end
		end

		# Start the agent running.
		#
		# This fires off the stimuli listeners and then waits.  If you want to
		# do anything else while this runs, you'll want to fire this in a
		# separate thread.
		#
		def run
			begin
				# Some memos (AMQPPublisher being the first) work best when
				# initialized when the agent starts up.  At some point in the
				# future, we might implement selective initialisation, but for
				# now we'll take the brutally-simple approach of getting
				# everything.
				(@memos || {}).keys.each { |k| send(k, &->(_){}) }

				@thread_group ||= ThreadGroup.new
				@runner_thread = Thread.current

				(stimuli || {}).each do |s|
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
			(@thread_group.list rescue []).each do |th|
				th.raise Brown::FinishSignal.new("agent finish")
			end

			(@thread_group.list rescue []).each do |th|
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

		def more_log_detail
			logger.level -= 1
		end

		def less_log_detail
			logger.level += 1
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

		def bind_queue(amqp_session:, queue_name:, exchange_name:, concurrency:)
			ch = amqp_session.create_channel
			ch.prefetch(concurrency)

			ch.queue(queue_name, durable: true).tap do |q|
				if exchange_name != ""
					begin
						q.bind(exchange_name)
					rescue Bunny::NotFound => ex
						logger.error { "bind failed: #{ex.message}" }
						sleep 5
						return bind_queue(
						         amqp_session: amqp_session,
						         queue_name: queue_name,
						         exchange_name: exchange_name,
						         concurrency: concurrency
						       )
					end
				end
			end
		end
	end

	# The logger for this agent.
	#
	# @return [Logger]
	#
	def logger
		self.class.logger
	end
end
