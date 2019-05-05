require_relative 'spec_helper'

describe "Brown::Agent::AMQPPublisher.new" do
	let(:session_mock)  { instance_double(Bunny::Session) }
	let(:channel_mock)  { instance_double(Bunny::Channel) }
	let(:exchange_mock) { instance_double(Bunny::Exchange) }

	before :each do
		allow(session_mock)
		  .to receive(:create_channel)
		  .and_return(channel_mock)
		allow(channel_mock)
		  .to receive(:exchange)
		  .and_return(exchange_mock)
	end

	context "with all defaults" do
		it "starts the session" do
			Brown::Agent::AMQPPublisher.new(amqp_session: session_mock)
		end

		it "creates a channel" do
			expect(session_mock).to receive(:create_channel)

			Brown::Agent::AMQPPublisher.new(amqp_session: session_mock)
		end

		it "creates an exchange" do
			expect(channel_mock)
			  .to receive(:exchange)
			  .with("", :type => :direct, :durable => true)
			  .and_return(exchange_mock)

			Brown::Agent::AMQPPublisher.new(amqp_session: session_mock)
		end
	end

	context "with custom exchange name" do
		it "passes the custom exchange name" do
			expect(channel_mock)
			  .to receive(:exchange)
			  .with("my.crazy.exchange", :type => :direct, :durable => true)
			  .and_return(exchange_mock)

			Brown::Agent::AMQPPublisher.new(
				amqp_session: session_mock,
				exchange_name: "my.crazy.exchange"
			)
		end
	end

	context "with custom exchange name and type" do
		it "passes the custom exchange name" do
			expect(channel_mock)
			  .to receive(:exchange)
			  .with("my.crazy.exchange", :type => :fanout, :durable => true)
			  .and_return(exchange_mock)

			Brown::Agent::AMQPPublisher.new(
			  amqp_session: session_mock,
			  exchange_name: "my.crazy.exchange",
			  exchange_type: :fanout
			)
		end
	end

	context "with a funky exchange config" do
		it "raises an appropriate error" do
			expect(channel_mock)
			  .to receive(:exchange)
			  .and_raise(
			     Bunny::PreconditionFailed.new(
			              "something bad happened",
			              channel_mock,
			              true
			            )
			   )

			expect do
				Brown::Agent::AMQPPublisher.new(amqp_session: session_mock)
			end.to raise_error(
			         Brown::Agent::AMQPPublisher::ExchangeError,
			         /Failed to open exchange: something bad happened/
			       )
		end
	end
end
