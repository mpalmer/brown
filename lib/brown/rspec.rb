require 'brown/test'

module Brown::SpecHelpers
	def self.included(mod)
		mod.let(:agent_env) { { "AMQP_URL" => "amqp://spec.example.invalid" } }
		mod.let(:agent) { described_class.new(agent_env) }

		if mod.described_class.respond_to?(:amqp_publishers)
			(mod.described_class.amqp_publishers || []).each do |publisher|
				mod.let(:"#{publisher[:name]}_publisher") { instance_double(Brown::Agent::AMQPPublisher, publisher[:name]) }
			end
		end

		mod.before(:each) do
			if described_class.respond_to?(:amqp_publishers)
				(described_class.amqp_publishers || []).each do |publisher|
					allow(agent).to receive(publisher[:name]).and_return(send(:"#{publisher[:name]}_publisher"))
				end
			end
		end
	end
end
