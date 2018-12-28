require_relative 'spec_helper'

describe "Brown::Agent::Stimulus#run" do
	uses_logger

	let(:proc_mock) { double(Object) }

	let(:in_q)  { Queue.new }

	class AgentClass < Brown::Agent
		def foo(mock)
			mock.oof
		end
	end

	let(:agent) { AgentClass.new({}) }

	let(:stimulus) do
		Brown::Agent::Stimulus.new(
			method:       agent.method(:foo),
			stimuli_proc: stimuli_proc,
			logger:       logger
		)
	end

	context "with a well-behaved stimuli proc" do
		let(:stimuli_proc) do
			->(worker) do
				begin
					worker.call(in_q.pop(true))
				rescue ThreadError
					stimulus.shutdown
				end
			end
		end

		it "runs OK in single-shot mode" do
			expect(proc_mock).to receive(:oof).once.and_return(true)
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
				.to receive(:oof)
				.and_raise(RuntimeError.new("howzat"))

			expect(logger).to receive(:error) do |&blk|
				expect(blk.call).to match(/Stimulus worker.*howzat.*RuntimeError/)
			end

			in_q.push(proc_mock)

			stimulus.run
		end
	end

	context "stimulus proc that loses its shit" do
		let(:stimuli_proc) do
			already_run = false
			->(worker) do
				if already_run
					stimulus.shutdown
				else
					already_run = true
					raise(RuntimeError.new("ffca8676"))
				end
			end
		end

		it "logs the error" do
			expect(logger).to receive(:error) do |&blk|
				expect(blk.call).to match(/ffca8676.*RuntimeError/)
			end

			stimulus.run
		end
	end
end
