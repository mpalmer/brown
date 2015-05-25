require_relative 'spec_helper'

describe "Brown::Agent::AMQPPublisher.new" do
	let(:session_mock)  { instance_double(Bunny::Session) }
	let(:channel_mock)  { instance_double(Bunny::Channel) }
	let(:exchange_mock) { instance_double(Bunny::Exchange) }

	before :each do
		allow(Bunny)
		  .to receive(:new)
		  .and_return(session_mock)
		allow(session_mock)
		  .to receive(:start)
		allow(session_mock)
		  .to receive(:create_channel)
		  .and_return(channel_mock)
		allow(channel_mock)
		  .to receive(:exchange)
		  .and_return(exchange_mock)
	end

	context "with all defaults" do
		it "passes the correct (default) URL" do
			expect(Bunny)
			  .to receive(:new)
			  .with("amqp://localhost", logger: instance_of(Logger))
			  .and_return(session_mock)

			Brown::Agent::AMQPPublisher.new
		end

		it "starts the session" do
			expect(session_mock).to receive(:start)

			Brown::Agent::AMQPPublisher.new
		end

		it "creates a channel" do
			expect(session_mock).to receive(:create_channel)

			Brown::Agent::AMQPPublisher.new
		end

		it "creates an exchange" do
			expect(channel_mock)
			  .to receive(:exchange)
			  .with("", :type => :direct, :durable => true)
			  .and_return(exchange_mock)

			Brown::Agent::AMQPPublisher.new
		end
	end

	context "with custom AMQP URL" do
		it "passes the custom URL" do
			expect(Bunny)
			  .to receive(:new)
			  .with("amqp://foo:s3kr1t@bar.example.com", logger: instance_of(Logger))
			  .and_return(session_mock)

			Brown::Agent::AMQPPublisher.new(
			  amqp_url: "amqp://foo:s3kr1t@bar.example.com"
			)
		end
	end

	context "with custom exchange name" do
		it "passes the custom exchange name" do
			expect(channel_mock)
			  .to receive(:exchange)
			  .with("my.crazy.exchange", :type => :direct, :durable => true)
			  .and_return(exchange_mock)

			Brown::Agent::AMQPPublisher.new(
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
			  exchange_name: "my.crazy.exchange",
			  exchange_type: :fanout
			)
		end
	end

	context "with a failed connection" do
		it "raises an appropriate error" do
			expect(session_mock)
			  .to receive(:start)
			  .and_raise(Bunny::TCPConnectionFailedForAllHosts)

			expect do
				Brown::Agent::AMQPPublisher.new
			end.to raise_error(
			         Brown::Agent::AMQPPublisher::BrokerError,
			         /localhost/
			       )
		end
	end

	context "with failed authentication" do
		it "raises an appropriate error" do
			expect(session_mock)
			  .to receive(:start)
			  .and_raise(Bunny::AuthenticationFailureError.new('', '', 0))

			expect do
				Brown::Agent::AMQPPublisher.new
			end.to raise_error(
			         Brown::Agent::AMQPPublisher::BrokerError,
			         /authentication.*localhost/i
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
				Brown::Agent::AMQPPublisher.new
			end.to raise_error(
			         Brown::Agent::AMQPPublisher::ExchangeError,
			         /Failed to open exchange: something bad happened/
			       )
		end
	end
end
