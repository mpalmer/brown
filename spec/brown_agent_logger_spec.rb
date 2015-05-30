require_relative './spec_helper'
require 'brown/agent'

describe "Brown::Agent.logger" do
	let(:mock_logger) { instance_double(Logger) }

	context "global logger" do
		before(:each) do
			Brown::Agent.logger = mock_logger
		end

		after(:each) do
			Brown::Agent.logger = nil
		end

		let(:agent_class) { Class.new(Brown::Agent) }

		it "sets the global logger" do
			expect(Brown::Agent.logger).to eq(mock_logger)
		end

		it "propagates to subclasses" do
			expect(agent_class.logger).to eq(mock_logger)
		end

		it "doesn't cache in subclasses" do
			expect(agent_class.logger).to eq(mock_logger)

			Brown::Agent.logger = :fake_logger

			expect(agent_class.logger).to eq(:fake_logger)
		end

		it "increases log detail" do
			expect(mock_logger)
			  .to receive(:level)
			  .with(no_args)
			  .and_return(2)
			expect(mock_logger)
			  .to receive(:level=)
			  .with(1)

			Brown::Agent.more_log_detail
		end

		it "decreases log detail" do
			expect(mock_logger)
			  .to receive(:level)
			  .with(no_args)
			  .and_return(2)
			expect(mock_logger)
			  .to receive(:level=)
			  .with(3)

			Brown::Agent.less_log_detail
		end
	end

	context "per-class logger" do
		let(:agent_class) do
			Class.new(Brown::Agent).tap do |k|
				k.logger = mock_logger
			end
		end

		it "sets the logger correctly" do
			expect(agent_class.logger).to eq(mock_logger)
		end

		it "doesn't modify the global logger" do
			expect(Brown::Agent.logger).to be_a(Logger)
			expect(Brown::Agent.logger).to_not eq(mock_logger)
		end
	end
end
