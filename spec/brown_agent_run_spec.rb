require_relative './spec_helper'
require 'brown/agent'

describe "Brown::Agent#run" do
	uses_logger

	context "with a single 'foo' stimulus" do
		let(:mock)        { double(Object) }
		let(:agent_class) do
			Class.new(Brown::Agent).tap do |k|
				k.stimulate(:foo) do
					mock.foo
					agent.stop
				end

				k.__send__(:define_method, :foo) {}
			end
		end
		let(:agent) { agent_class.new({}) }

		it "fires off the stimuli watcher" do
			expect(mock).to receive(:foo).at_least(:once)
			agent.start
		end
	end
end
