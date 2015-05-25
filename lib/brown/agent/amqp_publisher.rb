require 'bunny'

# Publish messages to an AMQP exchange.
#
class Brown::Agent::AMQPPublisher
	#:nodoc:
	# Sentinel to detect that we've been sent the "default" value,
	# since `nil` can, sometimes, be a valid value.
	NoValue = Module.new

	# The top-level exception class for all AMQPPublisher errors.
	#
	# If you want to just rescue *anything* untoward relating to an AMQP
	# Publisher, then catch this.  If you happen to get an instance of this
	# class, however, then something is wrong.  More wrong than what caused
	# the exception in the first place, even.
	#
	class Error < StandardError; end

	# Indicate a problem at the level of the AMQP broker.
	#
	# This could be an issue connecting (name resolution failure, network
	# connectivity problem, etc), or an authentication or access control
	# problem.  The message should indicate the exact problem.
	#
	class BrokerError < Error; end

	# There has been a problem with the exchange itself.
	#
	class ExchangeError < Error; end

	# Create a new AMQPPublisher.
	#
	# Setup an exchange in the AMQP broker, and allow the publishing of
	# messages to that exchange.
	#
	# @param amqp_url [#to_s] the AMQP broker to connect to, specified as a
	#   URL.  The scheme must be `amqp`.  Username and password should be
	#   given in the standard fashion (`amqp://<user>:<pass>@<host>`).
	#
	#   The path portion of AMQP URLs is totes spesh; if you want to
	#   connect to the default vhost (`/`) you either need to specify *no*
	#   trailing slash (ie `amqp://hostname`) or percent-encode the `/`
	#   vhost name (ie `amqp://hostname/%2F`).  Yes, this drives me nuts,
	#   too.
	#
	# @param exchange_type [Symbol] the type of exchange to create or publish
	#   to.  By default, the exchange is created as a *direct* exchange; this
	#   routes messages to their destination queue(s) based on the
	#   `routing_key` (set per-publisher or per-queue).  Other valid values
	#   for this option are `:direct`, `:topic`, and `:headers`.
	#
	# @param exchange_name [#to_s] the name of the exchange to create or
	#   publish to.  If not specified, then the "default" exchange is used,
	#   which is a direct exchange that routes to a queue with the same name
	#   as the routing key.
	#
	# @param routing_key [#to_s] The default "routing key" to attach to
	#   all messages sent via this publisher.  This can also be set (or
	#   overridden) on a per-message basis; see
	#   {Brown::Agent::AMQPPublisher#publish}.  If set to `nil`, no routing
	#   key will be set.
	#
	# @param message_type [#to_s] The default type for all messages sent via
	#   this publisher.  This can also be set (or overridden) on a
	#   per-message basis; see {Brown::Agent::AMQPPublisher#publish}.  If set
	#   to `nil`, no message type will be set by default.
	#
	# @param logger [Logger] somewhere to log everything.
	#
	# @param amqp_opts [Hash] is a "catch-all" hash for any weird and
	#   wonderful AMQP options you may wish to set by default for all
	#   messages you send via this publisher.  There are quite a number of
	#   rather esoteric options, which are not supported especially by
	#   Brown::Agent::AMQPPublisher, but if you really need them, they're
	#   here for you.  See [the relevant
	#   documentation](http://www.rubydoc.info/gems/bunny/Bunny/Exchange#publish-instance_method)
	#   for full details of every possible permutation.
	#
	# @raise [ArgumentError] if the parameters provided are problematic, such
	#   as specifying an invalid exchange type or exchange name.
	#
	# @raise [Brown::Agent::AMQPPublisher::BrokerError] if the attempt to
	#   connect to the broker fails, due to a lack of connection, or wrong
	#   credentials.
	#
	# @raise [Brown::Agent::AMQPPublisher::ExchangeError] if the attempt to
	#   create the exchange fails for some reason (such as the exchange
	#   already existing with a different configuration).
	#
	def initialize(amqp_url:      "amqp://localhost",
	               exchange_type: :direct,
	               exchange_name: "",
	               routing_key:   nil,
	               message_type:  nil,
	               logger:        Logger.new("/dev/null"),
	               **amqp_opts
	              )
		begin
			@amqp_session = Bunny.new(amqp_url, logger: logger)
			@amqp_session.start
		rescue Bunny::TCPConnectionFailed
			raise BrokerError,
			      "Failed to connect to #{amqp_url}"
		rescue Bunny::PossibleAuthenticationFailureError
			raise BrokerError,
			      "Authentication failed for #{amqp_url}"
		rescue StandardError => ex
			raise Error,
			      "Unknown error occured: #{ex.message} (#{ex.class})"
		end

		@amqp_channel = @amqp_session.create_channel

		begin
			@amqp_exchange = @amqp_channel.exchange(
			                   exchange_name,
			                   type: exchange_type,
			                   durable: true
			                 )
		rescue Bunny::PreconditionFailed => ex
			raise ExchangeError,
			      "Failed to open exchange: #{ex.message}"
		end

		@message_defaults = {
			:routing_key => routing_key,
			:type        => message_type
		}.merge(amqp_opts)

		@channel_mutex = Mutex.new
	end

	# Publish a message to the exchange.
	#
	# @param payload [#to_s] the "body" of the message to send.
	#
	# @param type [#to_s] override the default message type set in the
	#   publisher, just for this one message.
	#
	# @param routing_key [#to_s] override the default routing key set in the
	#   publisher, just for this one message.
	#
	# @param amqp_opts [Hash] is a "catch-all" hash for any weird and
	#   wonderful AMQP options you may wish to set.  There are quite a number
	#   of rather esoteric options, which are not supported especially by
	#   Brown::Agent::AMQPPublisher, but if you really need them, they're
	#   here for you.  See [the relevant
	#   documentation](http://www.rubydoc.info/gems/bunny/Bunny/Exchange#publish-instance_method)
	#   for full details of every possible permutation.
	#
	def publish(payload, type: NoValue, routing_key: NoValue, **amqp_opts)
		opts = @message_defaults.merge(
		          {
		            type:        type,
		            routing_key: routing_key
		          }.delete_if { |_,v| v == NoValue }
		       ).delete_if { |_,v| v.nil? }.merge(amqp_opts)

		if @amqp_exchange.name == "" and opts[:routing_key].nil?
			raise ExchangeError,
			      "Cannot send a message to the default exchange without a routing key"
		end

		@channel_mutex.synchronize do
			@amqp_exchange.publish(payload, opts)
		end
	end
end
