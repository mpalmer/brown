require_relative './spec_helper'
require 'brown/agent'

describe "Brown::Agent.run" do
	context "with a single 'foo' stimulus" do
		let(:mock)        { double(Object) }
		let(:test_proc)   { ->(_) { mock.foo; agent_class.stop } }
		let(:agent_class) do
			Class.new(Brown::Agent).tap do |k|
				k.stimulate(:foo) do
					mock.foo
					agent_class.stop
				end
			end
		end

		it "fires off the stimuli watcher" do
			expect(mock).to receive(:foo).at_least(1).times
			agent_class.run
		end
	end
end
