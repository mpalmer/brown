require_relative 'spec_helper'

describe "Brown::Agent.memo" do
	class VarAgent < Brown::Agent; end
	VarAgent.memo(:locked) { 42 }

	let(:agent) { VarAgent.new({}) }

	it "throws a tanty if we try to access an unsafe memo" do
		expect { agent.locked }.to raise_error(RuntimeError)
	end

	it "is OK to access via a block" do
		actual = nil

		agent.locked do |val|
			# Capture in here, but do the expectation outside, to catch the situation
			# where the block doesn't run, which -- if we were doing the expect
			# inside the block -- would erroneously pass.
			actual = val
		end

		expect(actual).to eq(42)
	end
end
