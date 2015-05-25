require_relative './spec_helper'
require 'brown/agent'

describe "Brown::Agent.stimulate" do
	context "with a single 'foo' stimulus" do
		let(:test_proc)   { ->() { nil } }
		let(:agent_class) do
			Class.new(Brown::Agent).tap { |k| k.stimulate(:foo, &test_proc) }
		end

		it "adds a stimulus" do
			expect(agent_class.send(:stimuli).length).to eq(1)
		end

		let(:stimulus) { agent_class.send(:stimuli).first }

		it "creates a Brown::Agent::Stimulus" do
			expect(stimulus.class).to eq(Brown::Agent::Stimulus)
		end

		it "stores the proc in the stimulus" do
			expect(stimulus.stimuli_proc).to eq(test_proc)
		end

		it "stores the method to call in the stimulus" do
			expect(stimulus.method_name).to eq(:foo)
		end

		it "stores the class to instantiate in the stimulus" do
			expect(stimulus.agent_class).to eq(agent_class)
		end
	end
end
