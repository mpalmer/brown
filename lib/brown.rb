# The "core" Brown module.  Nothing actually lives here.
module Brown
	#:nodoc:
	# Signals to a running stimulus or worker that it needs to die.
	#
	class StopSignal < Exception; end

	#:nodoc:
	# Signals to a running stimulus or worker that it needs to finish off
	# what it is doing and then terminate.
	#
	class FinishSignal < Exception; end
end

require_relative 'brown/agent'
require_relative 'brown/agent/amqp'
require_relative 'brown/agent/amqp_message'
require_relative 'brown/agent/amqp_publisher'
require_relative 'brown/agent/memo'
require_relative 'brown/agent/stimulus'
require_relative 'brown/agent/stimulus/metrics'
