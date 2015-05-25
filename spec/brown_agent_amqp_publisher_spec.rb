require_relative 'spec_helper'

describe "Brown::Agent.amqp_publisher" do
	let(:pub_mock) { instance_double(Brown::Agent::AMQPPublisher) }

	let(:agent_class) do
		Class.new(Brown::Agent)
	end

	context "with a name-only call" do
		before :each do
			agent_class.amqp_publisher :foo
		end

		it "doesn't create the AMQP publisher immediately" do
			expect(Brown::Agent::AMQPPublisher).to_not receive(:new)

			agent_class
		end

		it "creates an AMQP publisher when the agent starts" do
			expect(Brown::Agent::AMQPPublisher)
			  .to receive(:new)
			  .with(exchange_name: :foo)
			  .and_return(pub_mock)

			th = Thread.new { agent_class.run }
			sleep 0.001 until th.stop?
			agent_class.stop
		end

		it "makes the publisher available in a memo" do
			expect(Brown::Agent::AMQPPublisher)
			  .to receive(:new)
			  .with(exchange_name: :foo)
			  .and_return(pub_mock)

			expect(agent_class.foo).to eq(pub_mock)
		end
	end

	context "with an options-ish call" do
		before :each do
			agent_class.amqp_publisher :foo,
			                           amqp_url: "amqp://foo:bar@example.com"
		end

		it "passes the opts to the publisher" do
			expect(Brown::Agent::AMQPPublisher)
			  .to receive(:new)
			  .with(exchange_name: :foo, amqp_url: "amqp://foo:bar@example.com")
			  .and_return(pub_mock)

			expect(agent_class.foo).to eq(pub_mock)
		end
	end
end
