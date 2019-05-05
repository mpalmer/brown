# AMQP support for Brown agents.
#
# Including this module in your agent provides support for publishing and
# receiving AMQP messages from an AMQP broker, such as RabbitMQ.
#
# The methods in this module itself aren't particularly interesting to end-users;
# the good stuff is in {Brown::Agent::AMQP::ClassMethods}.
#
module Brown::Agent::AMQP
	private

	def self.included(mod)
		mod.string :AMQP_URL
		mod.prepend(Brown::Agent::AMQP::Initializer)
		mod.extend(Brown::Agent::AMQP::ClassMethods)
	end
end

require_relative "amqp/initializer"
require_relative "amqp/class_methods"
