# -*- encoding: utf-8 -*-

require 'extlib'
require 'murmurhash3'

module Brown::ACLLookup
	def get_by_hash(type)
		hashes[type]
	end
	module_function :get_by_hash

	def get_by_type(type)
		to_murmur32(type)
	end
	module_function :get_by_type

	# Look the key up in the cache. This defaults to the key being the hash.
	# If :by_type => true is passed in as the second argument then it will
	# perform the lookup in the type hash.
	#
	def include?(key, opts={})
		if opts[:by_type]
			!get_by_type(key).nil?
		else
			!get_by_hash(key).nil?
		end
	end
	module_function :include?

	def clear!
		@hashes = nil
	end
	module_function :clear!

	def hashes
		@hashes ||= begin
			map = ObjectSpace.each_object(Class).map do |k|
				[[to_murmur32(k), k], [k.to_s.split(/::/).last.snake_case, k]]
			end.flatten(1)
			Hash[map]
		end
	end
	module_function :hashes

	private

	# Convert the name to a base 36 murmur hash
	def to_murmur32(type)
		MurmurHash3::V32.murmur3_32_str_hash(type.to_s).to_s(36)
	end
	module_function :to_murmur32
end
