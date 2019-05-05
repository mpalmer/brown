require_relative 'spec_helper'

describe "Brown::Agent::AMQPPublisher#publish" do
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

	let(:message)   { "Climb Mount Shiitaki" }

	context "default publisher" do
		let(:publisher) { Brown::Agent::AMQPPublisher.new(amqp_session: session_mock) }

		before :each do
			allow(exchange_mock)
			  .to receive(:name)
			  .and_return("")
		end

		it "sends out a routing-key-enabled message" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "flingle")
			  .and_return(session_mock)

			publisher.publish(message, routing_key: "flingle")
		end

		it "sends out a typed, routed message" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, type: "hotmetal", routing_key: "flingle")
			  .and_return(session_mock)

			publisher.publish(message, type: "hotmetal", routing_key: "flingle")
		end

		it "freaks out if using the default exchange with no routing key" do
			expect do
				publisher.publish(message)
			end.to raise_error(
			         Brown::Agent::AMQPPublisher::ExchangeError,
			         "Cannot send a message to the default exchange without a routing key"
			       )
		end

		it "sends out a message with custom options" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(
			     message,
			     routing_key: "foo",
			     persistent: true,
			     content_type: "text/plain"
			   )
			  .and_return(session_mock)

			publisher.publish(
			            message,
			            routing_key: "foo",
			            persistent: true,
			            content_type: "text/plain"
			          )
		end
	end

	context "publisher with a routing key" do
		let(:publisher) { Brown::Agent::AMQPPublisher.new(amqp_session: session_mock, routing_key: "foo") }

		before :each do
			allow(exchange_mock)
			  .to receive(:name)
			  .and_return("")
		end

		it "sends out a message with the default routing key" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "foo")
			  .and_return(session_mock)

			publisher.publish(message)
		end

		it "sends out a typed message with the default routing key" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "foo", type: "hotmetal")
			  .and_return(session_mock)

			publisher.publish(message, type: "hotmetal")
		end

		it "sends out a message with an overridden routing key" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "flingle")
			  .and_return(session_mock)

			publisher.publish(message, routing_key: "flingle")
		end

		it "freaks out if we unset the default routing key" do
			expect do
				publisher.publish(message, routing_key: nil)
			end.to raise_error(
			         Brown::Agent::AMQPPublisher::ExchangeError,
			         "Cannot send a message to the default exchange without a routing key"
			       )
		end
	end

	context "publisher with a default message type" do
		let(:publisher) { Brown::Agent::AMQPPublisher.new(amqp_session: session_mock, message_type: "bar") }

		before :each do
			allow(exchange_mock)
			  .to receive(:name)
			  .and_return("")
		end

		it "sends out a message with the default type" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "flingle", type: "bar")
			  .and_return(session_mock)

			publisher.publish(message, routing_key: "flingle")
		end

		it "sends out a message with an overridden type" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "flingle", type: "lololol")
			  .and_return(session_mock)

			publisher.publish(message, routing_key: "flingle", type: "lololol")
		end

		it "sends out a message with an unset type" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, routing_key: "flingle")
			  .and_return(session_mock)

			publisher.publish(message, routing_key: "flingle", type: nil)
		end
	end

	context "publisher with a different exchange name" do
		let(:publisher) do
			Brown::Agent::AMQPPublisher.new(amqp_session: session_mock, exchange_name: "wombat")
		end

		before :each do
			allow(exchange_mock)
			  .to receive(:name)
			  .and_return("wombat")
		end

		it "sends out a message with no options" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(message, {})
			  .and_return(session_mock)

			publisher.publish(message)
		end
	end

	context "publisher with custom AMQP options" do
		let(:publisher) do
			Brown::Agent::AMQPPublisher.new(
			                amqp_session: session_mock,
			                routing_key: "foo",
			                persistent: true,
			                content_type: "text/plain"
			              )
		end

		before :each do
			allow(exchange_mock)
			  .to receive(:name)
			  .and_return("")
		end

		it "sends out a message with all the options set" do
			expect(exchange_mock)
			  .to receive(:publish)
			  .with(
			     message,
			     routing_key: "foo",
			     persistent: true,
			     content_type: "text/plain"
			   )
			  .and_return(session_mock)

			publisher.publish(message)
		end
	end
end
