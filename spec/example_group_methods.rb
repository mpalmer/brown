module ExampleGroupMethods
	def uses_logger
		let(:logger) { instance_double(Logger) }

		before(:each) do
			allow(Logger).to receive(:new).and_return(logger)
			allow(logger).to receive(:debug).with(instance_of(String))
			allow(logger).to receive(:info).with(instance_of(String))
			allow(logger).to receive(:error) { |p, &m| puts "#{p}: #{m.call}" }
			allow(logger).to receive(:level=).with(Logger::INFO)
			allow(logger).to receive(:filters=).with([])
			allow(logger).to receive(:formatter=).with(an_instance_of(Proc))
			allow(logger).to receive(:kind_of?).with(Logger).and_return(true)
		end
	end
end
