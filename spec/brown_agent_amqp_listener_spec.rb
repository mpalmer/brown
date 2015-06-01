require_relative 'spec_helper'

describe "Brown::Agent.amqp_listener" do
	let(:session_mock) { instance_double(Bunny::Session) }
	let(:channel_mock) { instance_double(Bunny::Channel) }
	let(:queue_mock)   { instance_double(Bunny::Queue) }
	let(:log_mock)     { instance_double(Logger) }

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
		  .to receive(:queue)
		  .and_return(queue_mock)
		allow(channel_mock)
		  .to receive(:prefetch)
		allow(queue_mock)
		  .to receive(:bind)
		allow(queue_mock)
		  .to receive(:subscribe) { agent_class.stop }
	end

	let(:agent_class) do
		Class.new(Brown::Agent).tap do |klass|
			klass.logger log_mock
		end
	end

	context "with no arguments" do
		let(:go) do
			agent_class.amqp_listener do
				# NOTHING!
			end

			agent_class.run
		end

		it "creates a Bunny session object" do
			expect(Bunny)
			  .to receive(:new)
			  .and_return(session_mock)

			go
		end

		it "starts the session" do
			expect(session_mock)
			  .to receive(:start)

			go
		end

		it "creates a channel" do
			expect(session_mock)
			  .to receive(:create_channel)
			  .and_return(channel_mock)

			go
		end

		it "sets the default prefetch" do
			expect(channel_mock)
			  .to receive(:prefetch)
			  .with(1)

			go
		end

		it "creates a queue" do
			expect(channel_mock)
			  .to receive(:queue)
			  .with("", durable: true)
			  .and_return(queue_mock)

			go
		end

		it "doesn't bind the queue to the default exchange" do
			expect(queue_mock)
			  .to_not receive(:bind)

			go
		end

		it "subscribes to the queue" do
			expect(queue_mock)
			  .to receive(:subscribe)
			  .with(manual_ack: true, block: true) { agent_class.stop }

			go
		end
	end

	context "with an exchange name" do
		let(:go) do
			agent_class.amqp_listener "some_exchange" do
				# NOTHING!
			end

			agent_class.run
		end

		it "creates a queue with the default name" do
			expect(channel_mock)
			  .to receive(:queue)
			  .with("-some_exchange", durable: true)
			  .and_return(queue_mock)

			go
		end

		it "binds the queue to the exchange" do
			expect(queue_mock)
			  .to receive(:bind)
			  .with("some_exchange")

			go
		end
	end

	context "with an array of exchange names" do
		let(:go) do
			agent_class.amqp_listener ["some_exchange", "other_exchange"] do
				# NOTHING!
			end

			agent_class.run
		end

		it "creates a queue with the default name" do
			expect(channel_mock)
			  .to receive(:queue)
			  .with("-some_exchange-other_exchange", durable: true)
			  .and_return(queue_mock)

			go
		end

		it "binds the queues to the exchange" do
			expect(queue_mock)
			  .to receive(:bind)
			  .with("some_exchange")
			expect(queue_mock)
			  .to receive(:bind)
			  .with("other_exchange")

			go
		end
	end

	context "with a different amqp_url" do
		let(:go) do
			agent_class.amqp_listener amqp_url: "amqp://example.com" do
				# NOTHING!
			end

			agent_class.run
		end

		it "creates a session with the special URL" do
			expect(Bunny)
			  .to receive(:new)
			  .with("amqp://example.com", logger: log_mock)

			go
		end
	end

	context "with a non-default concurrency" do
		let(:go) do
			agent_class.amqp_listener concurrency: 42 do
				# NOTHING!
			end

			agent_class.run
		end

		it "sets prefetch on the channel" do
			expect(channel_mock)
			  .to receive(:prefetch)
			  .with(42)

			go
		end
	end

	context "with a failed connection" do
		before(:each) do
			allow(agent_class)
			  .to receive(:sleep)
			allow(log_mock)
			  .to receive(:error)
			expect(session_mock)
			  .to receive(:start)
			  .and_raise(Bunny::TCPConnectionFailedForAllHosts)
		end

		let(:go) do
			agent_class.amqp_listener do
				# NOTHING!
			end

			agent_class.run
		end

		it "logs an error" do
			expect(log_mock).to receive(:error) do |&blk|
				expect(blk.call).to match(/Failed to connect.*localhost/)
			end

			go
		end

		it "sleeps for a bit then retries" do
			expect(agent_class)
			  .to receive(:sleep)
			  .with(5)
			expect(session_mock)
			  .to receive(:start)

			go
		end
	end

	context "with failed authentication" do
		before(:each) do
			allow(agent_class)
			  .to receive(:sleep)
			allow(log_mock)
			  .to receive(:error)
			expect(session_mock)
			  .to receive(:start)
			  .and_raise(Bunny::AuthenticationFailureError.new('', '', 0))
		end

		let(:go) do
			agent_class.amqp_listener do
				# NOTHING!
			end

			agent_class.run
		end

		it "logs an error" do
			expect(log_mock).to receive(:error) do |&blk|
				expect(blk.call).to match(/authentication.*localhost/i)
			end

			go
		end

		it "sleeps for a bit then retries" do
			expect(agent_class)
			  .to receive(:sleep)
			  .with(5)
			expect(session_mock)
			  .to receive(:start)

			go
		end
	end

	context "with an unknown exchange" do
		before(:each) do
			allow(log_mock)
			  .to receive(:error)
			allow(agent_class)
			  .to receive(:sleep)
			  .with(5)
			expect(queue_mock)
			  .to receive(:bind)
			  .with("unknown_exchange")
			  .and_raise(Bunny::NotFound.new("NOT_FOUND - no exchange 'unknown_exchange' in vhost '/'", '', false))
		end

		let(:go) do
			agent_class.amqp_listener "unknown_exchange" do
				# NOTHING!
			end

			agent_class.run
		end

		it "logs an error" do
			expect(log_mock).to receive(:error) do |&blk|
				expect(blk.call).to match(/bind.*no exchange 'unknown_exchange'/)
			end

			go
		end

		it "sleeps for a bit then retries" do
			expect(session_mock)
			  .to receive(:create_channel)
			  .and_return(channel_mock)
			expect(agent_class)
			  .to receive(:sleep)
			  .with(5)
			expect(session_mock)
			  .to receive(:create_channel)
			  .and_return(new_channel_mock = instance_double(Bunny::Channel))
			expect(new_channel_mock)
			  .to receive(:prefetch)
			  .with(1)
			expect(new_channel_mock)
			  .to receive(:queue)
			  .with("-unknown_exchange", durable: true)
			  .and_return(new_queue_mock = instance_double(Bunny::Queue))
			expect(new_queue_mock)
			  .to receive(:bind)
			  .with("unknown_exchange")
			expect(new_queue_mock)
			  .to receive(:subscribe) { agent_class.stop }
			go
		end
	end
end
