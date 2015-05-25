require_relative 'spec_helper'

describe "Brown::Agent::Stimulus#run" do
	let(:proc_mock) { double(Object) }
	let(:mock_logger) { instance_double(Logger) }

	let(:in_q)  { Queue.new }

	class AgentClass < Brown::Agent
		def foo(mock)
			mock.foo
		end
	end

	let(:stimulus) do
		Brown::Agent::Stimulus.new(
		  method_name:  :foo,
		  stimuli_proc: stimuli_proc,
		  agent_class:  AgentClass,
		  logger:       mock_logger
		)
	end

	context "with a well-behaved stimuli proc" do
		let(:stimuli_proc) do
			->(worker) do
				begin
					worker.call(in_q.pop(true))
				rescue ThreadError
					raise Brown::FinishSignal
				end
			end
		end

		it "runs OK in single-shot mode" do
			expect(proc_mock).to receive(:foo).once.and_return(true)
			in_q.push(proc_mock)

			stimulus.run(:once)
		end

		it "spawns a separate thread to handle each stimulus" do
			# Need to return a real Thread, because ThreadGroup, which Stimulus
			# uses internally, checks for that kind of thing
			expect(Thread).to receive(:new).twice.and_return(Thread.new {})

			2.times { in_q.push(proc_mock) }

			stimulus.run
		end

		it "logs an exploded stimulus worker" do
			expect(proc_mock)
			  .to receive(:foo)
			  .and_raise(RuntimeError.new("howzat"))

			expect(mock_logger).to receive(:error) do |&blk|
				expect(blk.call).to match(/Stimulus worker.*howzat.*RuntimeError/)
			end
			expect(mock_logger).to receive(:info)

			in_q.push(proc_mock)

			stimulus.run
		end

	end

	context "stimulus proc that loses its shit" do
		let(:stimuli_proc) { ->(worker) { proc_mock.foo } }

		it "logs the error" do
			expect(proc_mock)
			  .to receive(:foo)
			  .and_raise(RuntimeError.new("ffca8676"))
			expect(proc_mock)
			  .to receive(:foo)
			  .and_raise(Brown::FinishSignal)

			expect(mock_logger).to receive(:error) do |&blk|
				expect(blk.call).to match(/ffca8676.*RuntimeError/)
			end
			expect(mock_logger).to receive(:info)

			stimulus.run
		end
	end
end
