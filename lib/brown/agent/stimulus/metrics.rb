require "frankenstein/request"

# A bundle of metrics intended for a single arbitrary stimulus.
#
#
class Brown::Agent::Stimulus::Metrics
	# The Frankenstein::Request instance for the stimulus processing.
	attr_reader :processing_ruler

	# When the stimulus last fired.
	attr_reader :last_trigger

	def initialize(prefix, registry:)
		@processing_ruler = Frankenstein::Request.new(prefix, outgoing: false, registry: registry)
		@last_trigger     = registry.gauge(:"#{prefix}_last_trigger_timestamp_seconds", "When this stimulus was most recently triggered")
	end
end
