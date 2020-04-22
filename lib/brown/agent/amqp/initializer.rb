require "securerandom"
require "json"
require "yaml"

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

		initialize_publishers
	end

	def run
		initialize_listeners

		super
	end

	def shutdown
		amqp_session.close

		super
	end

	private

	def amqp_session
		@amqp_session ||= begin
			logger.debug(logloc) { "Initializing AMQP session" }
			Bunny.new(config.amqp_url, recover_from_connection_close: true, logger: config.logger).tap do |session|
				session.on_blocked { |blocked| logger.warn(logloc) { "AMQP connection has become blocked: #{blocked.reason}" } }
				session.on_unblocked { logger.info(logloc) { "AMQP connection has unblocked" } }
				session.start
			end
		end
	end

	def initialize_publishers
		(self.class.amqp_publishers || []).each do |publisher|
			logger.debug(logloc) { "Initializing AMQP publisher #{publisher}" }
			opts = { exchange_name: publisher[:name] }.merge(publisher[:opts])

			amqp_publisher = Brown::Agent::AMQPPublisher.new(amqp_session: amqp_session, **opts)

			define_singleton_method(publisher[:name]) { amqp_publisher }
		end
	end

	def initialize_listeners
		(self.class.amqp_listeners || []).each do |listener|
			logger.debug(logloc) { "Initializing AMQP listener #{listener}" }
			worker_method = "amqp_listener_worker_#{SecureRandom.uuid}".to_sym
			define_singleton_method(worker_method, listener[:callback])

			@stimuli ||= []
			@stimuli << {
				name: "amqp_listener_#{listener[:exchange_list].join("_").gsub(/[^A-Za-z0-9_]/, '_').gsub(/__+/, "_")}",
				method: method(worker_method),
				stimuli_proc: proc do |worker|
					consumer = queue(listener).subscribe(manual_ack: true) do |di, prop, payload|
						if listener[:autoparse]
							logger.debug(logloc) { "Attempting to autoparse against Content-Type: #{prop.content_type.inspect}" }
							case prop.content_type
							when "application/json"
								logger.debug(logloc) { "Parsing as JSON" }
								payload = JSON.parse(payload)
							when "application/x.yaml"
								logger.debug(logloc) { "Parsing as YAML" }
								payload = YAML.load(payload)
							when "application/vnd.brown.object.v1"
								logger.debug(logloc) { "Parsing as Brown object, allowed classes: #{listener[:allowed_classes]}" }
								begin
									payload = YAML.safe_load(payload, listener[:allowed_classes])
								rescue Psych::DisallowedClass => ex
									logger.error(logloc) { "message rejected: #{ex.message}" }
									di.channel.nack(di.delivery_tag, false, false)
									next
								end
							end
						end

						worker.call Brown::Agent::AMQPMessage.new(di, prop, payload)
					end

					while consumer&.channel&.status == :open do
						logger.debug(logloc) { "stimuli_proc for #{listener[:queue_name]} having a snooze" }
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
				exchange_list: listener[:exchange_list].map(&:to_s),
				concurrency:   listener[:concurrency],
				routing_key:   listener[:routing_key],
				predeclared:   listener[:predeclared],
			)
		rescue StandardError => ex
			log_exception(ex) { "Unknown error while binding queue #{listener[:queue_name].inspect} to exchange list #{listener[:exchange_list].inspect}" }
			sleep 5
			retry
		end
	end

	def bind_queue(queue_name:, exchange_list:, concurrency:, routing_key: nil, predeclared: false)
		ch = amqp_session.create_channel
		ch.prefetch(concurrency)

		ch.queue(queue_name, durable: true, no_declare: predeclared).tap do |q|
			next if predeclared
			exchange_list.each do |exchange_name|
				if exchange_name != ""
					begin
						q.bind(exchange_name, routing_key: routing_key)
					rescue Bunny::NotFound => ex
						logger.error { "bind failed: #{ex.message}" }
						sleep 5
						return bind_queue(
						       queue_name:    queue_name,
						       exchange_list: exchange_list,
						       concurrency:   concurrency,
						       routing_key:   routing_key,
						      )
					end
				end
			end
		end
	end
end
