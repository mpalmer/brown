require_relative 'spec_helper'

describe "Brown::Agent.every" do
	let(:mock) { double(Object) }

	let(:agent_class) do
		Class.new(Brown::Agent).tap do |klass|
			klass.memo(:mock)   { mock }

			klass.every 5 do
				mock { |m| m.tick }
			end
		end
	end

	it "does things over and over again" do
		expect(agent_class).to receive(:sleep).with(5).thrice
		expect(agent_class).to receive(:sleep).with(5) { agent_class.stop }

		expect(mock).to receive(:tick).thrice

		agent_class.run
	end
end
