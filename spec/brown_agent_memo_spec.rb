require_relative 'spec_helper'

describe "Brown::Agent.memo" do
	class VarAgent < Brown::Agent; end
	VarAgent.safe_memo(:foo) { rand(1000000) }
	VarAgent.memo(:locked)   { 42 }

	it "is only evaluated once even when called multiple times" do
		i = VarAgent.new
		val = i.foo
		expect(i.foo).to eq(val)
	end

	it "is only evaluated once even with multiple instances" do
		val = VarAgent.new.foo
		expect(VarAgent.new.foo).to eq(val)
	end

	it "is accessable in a block" do
		expected = VarAgent.new.foo
		val = nil
		VarAgent.new.foo { |v| val = v }

		expect(val).to eq(expected)
	end

	it "is accessible on the class" do
		expect(VarAgent.foo).to be_an(Integer)
	end

	it "returns the same value on the class and instance" do
		val = VarAgent.new.foo
		expect(VarAgent.foo).to eq(val)
	end

	it "throws a tanty if we try to access an unsafe memo" do
		expect { VarAgent.new.locked }.to raise_error(RuntimeError)
	end
end
