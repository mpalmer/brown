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
	def initialize(blk, safe=false)
		@blk   = blk
		@mutex = Mutex.new
		@safe  = safe
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
	def value
		if block_given?
			@mutex.synchronize { yield cached_value }
			nil
		else
			if @safe
				cached_value
			else
				raise RuntimeError,
				      "Access to unsafe agent variable prohibited"
			end
		end
	end

	private

	# A "raw" (unsafe) accessor to the cached value, or generate the value
	# and then cache it.
	#
	# @return [Object]
	#
	def cached_value
		@cached_value ||= @blk.call
	end
end
