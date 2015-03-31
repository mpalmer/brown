# Remove any pre-existing activation of eventmachine, so that `eventmachine-le`
# takes priority
$:.delete_if { |d| d =~ /\/eventmachine-\d/ }

require 'eventmachine-le'
require 'amqp'
require 'uri'

require 'brown/logger'

module Brown::ModuleMethods
	include Brown::Logger

	attr_reader :connection, :log_level

	def compile_acls
		@compiler = ACLCompiler.new
		@compiler.compile
	end

	def config
		Hash.new { |h,k| h[k] = Hash.new { |h,k| h[k] = "" } }
	end

	def running?
		EM.reactor_running?
	end

	def start(opts={})
		@log_level = opts[:log_level] || "info"

		# Why these are not the defaults, I will never know
		EM.epoll if EM.epoll?
		EM.kqueue if EM.kqueue?

		connection_settings = {
		  :on_tcp_connection_failure          => method(:tcp_connection_failure_handler),
		  :on_possible_authentication_failure => method(:authentication_failure_handler)
		}

		AMQP.start(opts[:server_url], connection_settings) do |connection|
			EM.threadpool_size = 1
			@connection = connection

			connection.on_connection do
				logger.info { "Connected to: AMQP Broker: #{broker_identifier(connection)}" }
			end

			connection.on_tcp_connection_loss do |connection, settings|
				logger.info { "Reconnecting to AMQP Broker: #{broker_identifier(connection)} in 5s" }
				connection.reconnect(false, 5)
			end

			connection.after_recovery do |connection|
				logger.info { "Connection with AMQP Broker restored: #{broker_identifier(connection)}" }
			end

			connection.on_error do |connection, connection_close|
				# If the broker is gracefully shutdown we get a 320. Log a nice message.
				if connection_close.reply_code == 320
					logger.info { "AMQP Broker shutdown: #{broker_identifier(connection)}" }
				else
					logger.warn { connection_close.reply_text }
				end
			end

			# This will be the last thing run by the reactor.
			shutdown_hook { logger.debug { "Reactor Stopped" } }

			yield if block_given?
		end
	end

	def shutdown_hook(&block)
		EM.add_shutdown_hook(&block)
	end

	def stop(immediately=false, &blk)
		shutdown_hook(&blk) if blk

		if running?
			if immediately
				EM.next_tick do
					@connection.close { EM.stop_event_loop }
				end
			else
				EM.add_timer(1) do
					@connection.close { EM.stop_event_loop }
				end
			end
		else
			logger.fatal { "Eventmachine is not running, exiting with prejudice" }
			exit!
		end
	end

	private

	def tcp_connection_failure_handler(settings)
		# Only display the following settings.
		s = settings.select { |k,v| ([:user, :pass, :vhost, :host, :port, :ssl].include?(k)) }

		logger.fatal { "Cannot connect to the AMQP server." }
		logger.fatal { "Is the server running and are the connection details correct?" }
		logger.info { "Details:" }
		s.each do |k,v|
			logger.info { " Setting: %-7s%s" %  [k, v] }
		end
		EM.stop
	end

	def authentication_failure_handler(settings)
		# Only display the following settings.
		s = settings.select { |k,v| [:user, :pass, :vhost, :host].include?(k) }

		logger.fatal { "Authentication failure." }
		logger.info { "Details:" }
		s.each do |k,v|
			logger.info { " Setting: %-7s%s" %  [k, v] }
		end
		EM.stop
	end

	def broker_identifier(connection)
		broker = connection.broker.properties
		"#{connection.broker_endpoint}, (#{broker['product']}/v#{broker['version']})"
	end
end
