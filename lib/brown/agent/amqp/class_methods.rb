require 'logger'
require 'securerandom'

# Class-level AMQP support for Brown agents.
#
# These methods are intended to be applied to a `Brown::Agent` subclass, so you
# can use them to define new AMQP listeners and publishers in your agent classes.
# You should not attempt to extend your classes directly with this module; the
# {Brown::Agent::AMQP} module should handle that for you automatically.
#
module Brown::Agent::AMQP::ClassMethods
	attr_reader :amqp_publishers, :amqp_listeners

	# Declare an AMQP publisher, and create an AMQP exchange to publish to.
	#
	# On the assumption that you already know [how exchanges
	# work](http://www.rabbitmq.com/tutorials/amqp-concepts.html), lets
	# just dive right in.
	#
	# This method creates an accessor method on your agent class, named after the
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
		@amqp_publishers ||= []
		@amqp_publishers << { name: name, opts: publisher_opts }
	end

	# Declare a stimulus to listen for messages from an AMQP broker.
	#
	# When the agent is started, we will setup a queue, bound to the exchange
	# specified by the `exchange_name` argument, and then proceed to hoover up
	# all the messages we can.
	#
	# The name of the queue that is created by default is derived from the
	# agent class name and the exchange name being bound to.  This allows
	# for multiple instances of the same agent, running in separate
	# processes or machines, to share the same queue of messages to
	# process, for throughput or redundancy reasons.
	#
	# @param exchange_name [#to_s, Array<#to_s>] the name of the exchange
	#   to bind to.  You can also specify an array of exchange names, to
	#   have all of them put their messages into the one queue.  This can
	#   be dangerous, because you need to make sure that your message
	#   handler can process the different types of messages that might be
	#   sent to the different exchangs.
	#
	# @param queue_name [#to_s] the name of the queue to create, if you
	#   don't want to use the class-derived default for some reason.
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
	# @param autoparse [Boolean] if your messages are all of a single
	#   content type, and the first thing you do on receiving a message is to
	#   call `JSON.parse(msg.payload)`, then you can turn on `autoparse`, and
	#   *as long as the message content-type is set correctly*, your messages
	#   will be parsed into native data structures before being turned into the
	#   `payload`.  This also enables automatic deserialization of object
	#   messages.
	#
	# @param allowed_classes [Array<Class>] a list of classes which are
	#   permitted to be instantiated when a message's `content_type` attribute
	#   indicates it is a serialized object.  If a message is received that
	#   contains a class not in the list (even if that object is embedded inside
	#   the message itself), the message will be rejected.
	#
	# @param routing_key [#to_s] if specified, then the queue that is created
	#   will be bound to the exchange with a defined routing key.
	#
	# @param predeclared [Boolean] indicates that the necessary queues and
	#   bindings are already in place, and thus no declarations should be
	#   made to the AMQP broker.
	#
	# @param reject_on_error [Boolean] by default, if an uncaught exception
	#   is raised during message handling, an error will be logged and the
	#   listener will not process any new messages.  However, if
	#   `reject_on_error: true`, then instead the message will be rejected, and
	#   processing will continue
	#
	# @param blk [Proc] is called every time a message is received from
	#   the queue, and an instance of {Brown::Agent::AMQPMessage} will
	#   be passed as the sole argument.
	#
	# @yieldparam message [Brown::Agent::AMQPMessage] is passed to `blk`
	#   each time a message is received from the queue.
	#
	def amqp_listener(exchange_name = "",
	                  queue_name:      nil,
	                  concurrency:     1,
	                  autoparse:       false,
	                  allowed_classes: nil,
	                  routing_key:     nil,
	                  predeclared:     false,
	                  reject_on_error: false,
	                  &blk
	                 )
		exchange_list = (Array === exchange_name ? exchange_name : [exchange_name]).map(&:to_s)

		if queue_name.nil?
			munged_exchange_list = exchange_list.map { |n| n.to_s == "" ? "" : "-#{n.to_s}" }.join
			queue_name = self.name.to_s + munged_exchange_list + (routing_key ? ":#{routing_key}" : "")
		end

		@amqp_listeners ||= []
		@amqp_listeners << {
			exchange_list:   exchange_list,
			queue_name:      queue_name,
			concurrency:     concurrency,
			autoparse:       autoparse,
			allowed_classes: allowed_classes,
			routing_key:     routing_key,
			callback:        blk,
			predeclared:     predeclared,
			reject_on_error: reject_on_error,
		}
	end
end
