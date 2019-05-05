require "securerandom"

# Methods that have to be prepended in order to work properly.
#
module Brown::Agent::AMQP::Initializer
	def initialize(*_)
		begin
			super
		rescue ArgumentError => ex
			if ex.message =~ /wrong number of arguments.*expected 0/
				super()
			else
				raise
			end
		end

		initialize_connection
		initialize_publishers
		initialize_listeners
	end

	def shutdown
		@amqp_session.close

		super
	end

	private

	def initialize_connection
		logger.debug(logloc) { "Initializing AMQP session" }
		@amqp_session = Bunny.new(config.amqp_url, recover_from_connection_close: true)
		@amqp_session.start
	end

	def initialize_publishers
		(self.class.amqp_publishers || []).each do |publisher|
			logger.debug(logloc) { "Initializing AMQP publisher #{publisher}" }
			opts = { exchange_name: publisher[:name] }.merge(publisher[:opts])

			define_singleton_method(publisher[:name]) do
				iv = :"@#{publisher[:name]}"
				# It's memoisation, Jim, but not as *we* know it
				instance_variable_get(iv) || instance_variable_set(iv, Brown::Agent::AMQPPublisher.new(amqp_session: @amqp_session, **opts))
			end
		end
	end

	def initialize_listeners
		(self.class.amqp_listeners || []).each do |listener|
			logger.debug(logloc) { "Initializing AMQP listener #{listener}" }
			worker_method = "amqp_listener_worker_#{SecureRandom.uuid}".to_sym
			define_singleton_method(worker_method, listener[:callback])

			@stimuli ||= []
			@stimuli << {
				method: method(worker_method),
				stimuli_proc: proc do |worker|
					consumer = queue(listener).subscribe(manual_ack: true) do |di, prop, payload|
						worker.call Brown::Agent::AMQPMessage.new(di, prop, payload)
					end

					logger.debug(logloc) { "stimuli_proc for #{listener[:queue_name]} having a snooze" }
					while consumer&.channel&.status == :open do
						sleep
					end
				end
			}
		end
	end

	def queue(listener)
		@queue_cache ||= {}
		@queue_cache[listener] ||= begin
			bind_queue(
				queue_name:    listener[:queue_name],
				exchange_list: listener[:exchange_list],
				concurrency:   listener[:concurrency],
			)
		rescue StandardError => ex
			log_exception(ex) { "Unknown error while binding queue #{listener[:queue_name].inspect} to exchange list #{listener[:exchange_list].inspect}" }
			sleep 5
			retry
		end
	end

	def bind_queue(queue_name:, exchange_list:, concurrency:)
		ch = @amqp_session.create_channel
		ch.prefetch(concurrency)

		ch.queue(queue_name, durable: true).tap do |q|
			exchange_list.each do |exchange_name|
				if exchange_name != ""
					begin
						q.bind(exchange_name)
					rescue Bunny::NotFound => ex
						logger.error { "bind failed: #{ex.message}" }
						sleep 5
						return bind_queue(
						       queue_name: queue_name,
						       exchange_list: exchange_list,
						       concurrency: concurrency
						      )
					end
				end
			end
		end
	end
end
