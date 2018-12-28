require_relative 'spec_helper'

require "brown/agent/amqp"

describe "Brown::Agent.amqp_publisher" do
	let(:pub_mock) { instance_double(Brown::Agent::AMQPPublisher) }

	let(:agent_class) do
		Class.new(Brown::Agent).tap do |c|
			c.include(Brown::Agent::AMQP)
			c.amqp_publisher :foo
		end
	end
	let(:agent) { agent_class.new({}) }

	context "with a name-only call" do
		it "doesn't create the AMQP publisher immediately" do
			expect(Brown::Agent::AMQPPublisher).to_not receive(:new)

			agent_class.new({})
		end

		it "makes the publisher available in a method" do
			expect(Brown::Agent::AMQPPublisher)
				.to receive(:new)
				.with(exchange_name: :foo)
				.and_return(pub_mock)

			expect(agent.foo).to eq(pub_mock)
		end
	end

	context "with an options-ish call" do
		before :each do
			agent_class.amqp_publisher :bar,
			                           amqp_url: "amqp://foo:bar@example.com"
		end

		it "passes the opts to the publisher" do
			expect(Brown::Agent::AMQPPublisher)
				.to receive(:new)
				.with(exchange_name: :bar, amqp_url: "amqp://foo:bar@example.com")
				.and_return(pub_mock)

			expect(agent.bar).to eq(pub_mock)
		end
	end
end
