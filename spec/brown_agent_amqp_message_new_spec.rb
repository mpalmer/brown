require_relative 'spec_helper'

describe "Brown::Agent::AMQPMessage" do
	let(:di_mock) { instance_double(Bunny::DeliveryInfo) }
	let(:p_mock)  { instance_double(Bunny::MessageProperties) }
	let(:payload) { "I'm in a bottle!" }

	let(:msg) { Brown::Agent::AMQPMessage.new(di_mock, p_mock, payload) }

	it "provides the payload" do
		expect(msg.payload).to eq("I'm in a bottle!")
	end

	it "provides a facility to ack the message" do
		expect(di_mock)
		  .to receive(:channel)
		  .with(no_args)
		  .and_return(channel_mock = instance_double(Bunny::Channel))
		expect(di_mock)
		  .to receive(:delivery_tag)
		  .with(no_args)
		  .and_return("you're it!")
		expect(channel_mock)
		  .to receive(:ack)
		  .with("you're it!")

		msg.ack
	end
end
