require 'brown/test'

RSpec.configure do |c|
	c.after(:each) do
		ObjectSpace.each_object(Class).each do |klass|
			if klass != Brown::Agent and klass.ancestors.include?(Brown::Agent)
				klass.reset_memos
			end
		end
	end
end
