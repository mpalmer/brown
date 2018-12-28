require_relative 'spec_helper'

describe "Brown::Agent.every" do
	uses_logger

	let(:mock) { double(Object) }

	let(:agent_class) do
		Class.new(Brown::Agent).tap do |klass|
			klass.memo(:mock) { mock }

			klass.every 5 do
				mock { |m| m.tick }
			end
		end
	end
	let(:agent) { agent_class.new({}) }

	it "does things over and over again" do
		n = 0
		allow(Kernel).to receive(:sleep) { n += 1; agent.stop if n > 3 }
		expect(mock).to receive(:tick).thrice

		agent.start
		expect(Kernel).to have_received(:sleep).at_least(3).times
	end
end
