# A message received from an AMQP broker.
#
# This is what you will get passed to you when you use
# {Brown::Agent.amqp_listener} to point a shell-like at an exchange.  It
# allows you to get the message itself, all of the message's metadata, and
# also act on the message by acknowledging it so the broker can consider it
# "delivered".
#
class Brown::Agent::AMQPMessage
	# The body of the message.
	#
	# Depending on the listener configuration, this may either be a string
	# representing the raw message, or else a deserialized object of some
	# sort.  See the documentation for the amqp_listener method's `autoparse`
	# and `allowed_classes` parameters for more details.
	#
	# @return [Object]
	#
	attr_reader :payload

	# Create a new message.  The arguments are a straight copy of what you
	# get yielded from `Bunny::Queue#subscribe`, or what gets returned from
	# `Bunny::Queue#pop`.
	#
	# @param delivery_info [Bunny::DeliveryInfo, Bunny::GetResponse]
	#
	# @param properties [Bunny::MessageProperties]
	#
	# @param payload [String]
	#
	def initialize(delivery_info, properties, payload)
		@delivery_info, @properties, @payload = delivery_info, properties, payload
	end

	# Acknowledge that this message has been processed.
	#
	# The broker needs to know that each message has been processed, before
	# it will remove the message from the queue entirely.  It also won't send
	# more than a certain number of messages at once, so until you ack a
	# message, you won't get another one.
	#
	def ack
		@delivery_info.channel.ack(@delivery_info.delivery_tag)
	end

	# Decline to handle this message, and requeue for later
	#
	# If, for some reason, the agent can't successfully process this message
	# right *now*, but you'd like it to be processed again later, then you
	# can ask for it to be requeued using this handy-dandy method.
	#
	def requeue
		@delivery_info.channel.nack(@delivery_info.delivery_tag, false, true)
	end

	# Decline to handle this message, now and forever
	#
	# If you want to dead-letter (or just disappear) a message, call this
	# method, and it will cease to exist.
	#
	def reject
		@delivery_info.channel.nack(@delivery_info.delivery_tag, false, false)
	end
end
