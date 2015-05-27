#:nodoc:
# A thread-safe agent "memo".
#
# This is the "behind the scenes" code that supports "agent memos", objects
# which are shared across all instances of a given agent.
#
# All of the interesting documentation about how agent memos work is in
# {Brown::Agent::ClassMethods.memo} and
# {Brown::Agent::ClassMethods.safe_memo}.
#
class Brown::Agent::Memo
	# Spawn a new memo.
	#
	# @param blk [Proc] the block to call to get the value of the memo.
	#
	# @param safe [Boolean] whether or not the value in the memo is
	#   inherently thread-safe for access.  This should only be set when the
	#   object cannot be changed, or when the object has its own locking to
	#   protect against concurrent access.  The default is to mark the
	#   memoised object as "unsafe", in which case all access to the variable
	#   must be in a block, which is itself executed inside a mutex.
	#
	def initialize(blk, safe=false, test=false)
		@blk         = blk
		@value_mutex = Mutex.new
		@attr_mutex  = Mutex.new
		@safe        = safe
		@test        = test
	end

	# Retrieve the value of the memo.
	#
	# @return [Object, nil] if called without a block, this will return
	#   the object which is the value of the memo; otherwise, `nil`.
	#
	# @yield [Object] the object which is the value of the memo.
	#
	# @raise [RuntimeError] if called on an unsafe memo without passing a
	#   block.
	#
	def value(test=nil)
		if block_given?
			@value_mutex.synchronize { yield cached_value }
			nil
		else
			if @safe || (@test && test == :test)
				cached_value
			else
				raise RuntimeError,
				      "Access to unsafe agent variable prohibited"
			end
		end
	end

	private

	# Retrieve or generate the cached value.
	#
	# @return [Object]
	#
	def cached_value
		@attr_mutex.synchronize { @cached_value ||= @blk.call }
	end
end
