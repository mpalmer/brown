require_relative './spec_helper'
require 'brown/agent'

describe "Brown::Agent.logger" do
	context "global logger" do
		before(:each) do
			Brown::Agent.logger = :not_a_real_logger_natch
		end
		
		after(:each) do
			Brown::Agent.logger = nil
		end

		let(:agent_class) { Class.new(Brown::Agent) }
		
		it "sets the global logger" do
			expect(Brown::Agent.logger).to eq(:not_a_real_logger_natch)
		end
		
		it "propagates to subclasses" do
			expect(agent_class.logger).to eq(:not_a_real_logger_natch)
		end
		
		it "doesn't cache in subclasses" do
			expect(agent_class.logger).to eq(:not_a_real_logger_natch)
			
			Brown::Agent.logger = :another_unreal_logger
			
			expect(agent_class.logger).to eq(:another_unreal_logger)
		end
	end

	context "per-class logger" do
		let(:agent_class) do
			Class.new(Brown::Agent).tap do |k|
				k.logger = :this_isnt_a_real_logger_either
			end
		end
		
		it "sets the logger correctly" do
			expect(agent_class.logger).to eq(:this_isnt_a_real_logger_either)
		end
		
		it "doesn't modify the global logger" do
			expect(Brown::Agent.logger).to be_a(Logger)
		end
	end
end
