require 'bunny'
require 'json'
require 'service_skeleton/logging_helpers'
require 'yaml'

# Publish messages to an AMQP exchange.
#
class Brown::Agent::AMQPPublisher
	include ServiceSkeleton::LoggingHelpers

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
	# @param amqp_session [Bunny::Session] an active session with the AMQP
	#   server.  Typically this will be the agent's `@amqp_session` variable.
	#
	# @param exchange_type [Symbol] the type of exchange to create or publish
	#   to.  By default, the exchange is created as a *direct* exchange; this
	#   routes messages to their destination queue(s) based on the
	#   `routing_key` (set per-publisher or per-queue).  Other valid values
	#   for this option are `:fanout`, `:topic`, and `:headers`.
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
	def initialize(amqp_session:,
	               exchange_type: :direct,
	               exchange_name: "",
	               routing_key:   nil,
	               message_type:  nil,
	               logger:        Logger.new("/dev/null"),
	               **amqp_opts
	              )
		@logger = logger
		@amqp_channel = amqp_session.create_channel

		begin
			@logger.debug(logloc) { "Initializing exchange #{exchange_name.inspect}" }
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
	# A message can be provided in the `payload` parameter in one of several
	# ways:
	#
	# * as a string, in which case the provided string is used as the message
	#   payload as-is, with no further processing or added metadata.
	#
	# * as a single-element hash, in which case the key is used as the identifier
	#   of the serialization format (either `:yaml` or `:json`), while the value
	#   is serialized by calling the appropriate conversion method (`.to_yaml` or
	#   `.to_json`, as appropriate) and the resulting string is used as the message
	#   payload.  The message's `content_type` attribute is set appropriately, also,
	#   allowing for automatic deserialization at the receiver.
	#
	#   This payload format is best used where you have complex structured data to
	#   pass around between system components with very diverse implementation
	#   environments, or where very loose coupling is desired.
	#
	# * as an arbitrary object, in which case the object is serialized in a form
	#   which allows it to be transparently deserialized again into a native
	#   Ruby object at the other end.
	#
	#   This payload format is most appropriate when you're deploying a
	#   tightly-coupled system where all the consumers are Brown agents, or at
	#   least all Ruby-based.
	#
	# @param payload [String, Hash<Symbol, Object>, Object] the content of the
	#   message to send.  There are several possibilities for what can be passed
	#   here, and how it is encoded into an AMQP message, as per the description
	#   above.
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
		@logger.debug(logloc) { "Publishing message #{payload.inspect}, type: #{type.inspect}, routing_key: #{routing_key.inspect}, options: #{amqp_opts.inspect}" }

		opts = @message_defaults.merge(
		          {
		            type:        type,
		            routing_key: routing_key
		          }.delete_if { |_,v| v == NoValue }
		       ).delete_if { |_,v| v.nil? }.merge(amqp_opts)

		if payload.is_a?(Hash)
			if payload.length != 1
				raise ArgumentError,
					   "Payload hash must have exactly one element"
			end

			case payload.keys.first
			when :json
				@logger.debug(logloc) { "JSON serialisation activated" }
				opts[:content_type] = "application/json"
				payload = payload.values.first.to_json
			when :yaml
				@logger.debug(logloc) { "YAML serialisation activated" }
				opts[:content_type] = "application/x.yaml"
				payload = payload.values.first.to_yaml
			else
				raise ArgumentError,
				      "Unknown format type: #{payload.keys.first.inspect} (must be :json or :yaml)"
			end
		elsif !payload.is_a?(String)
			payload = payload.to_yaml
			opts[:content_type] = "application/vnd.brown.object.v1"
		end

		if @amqp_exchange.name == "" and opts[:routing_key].nil?
			raise ExchangeError,
			      "Cannot send a message to the default exchange without a routing key"
		end

		@channel_mutex.synchronize do
			@amqp_exchange.publish(payload, opts)
			@logger.debug(logloc) { "... and it's gone" }
		end
	end
end
