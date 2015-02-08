module Brown; end

Dir["#{__dir__}/brown/*.rb"].each { |f| require f }

Brown.extend Brown::ModuleMethods
