#:nodoc:
#
# A mock form of the AMQPMessage class, only useful for testing.
#
#
class Brown::Agent::AMQPMessageMock
	attr_reader :payload

	def initialize(payload:)
		@payload = payload
		@acked   = false
	end

	# Record an ack.
	def ack
		if @acked
			raise RuntimeError,
			      "Cannot ack a message twice"
		end

		@acked = true
	end

	# Check we acked.
	def acked?
		@acked
	end
end
