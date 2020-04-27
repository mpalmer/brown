require 'logger'
require 'rb-inotify'
require 'securerandom'

# Class-level inotify support for Brown agents.
#
# These methods are intended to be applied to a `Brown::Agent` subclass, so you
# can use them to define new file watchers in your agent.
# You should not attempt to extend your classes directly with this module; the
# {Brown::Agent::FileWatch} module should handle that for you automatically.
#
module Brown::Agent::FileWatch::ClassMethods
	attr_reader :file_watchers

	# Watch one or more files or directories for modification.
	#
	# If a change is detected on any of the paths you list, then the associated
	# block of code will be executed.  If a path is a directory, then the entire
	# directory hierarchy will be watched recursively for any file or directory
	# creation, deletion, renaming, ormodification.  If the path is a file, it
	# will be watched for modification.  In either case, the path being
	# specified must already exist.
	#
	# @yieldparam event [INotify::Event] the raw `INotify::Event` that
	#   caused the block to be called.
	#
	def watch(*paths, &blk)
		@watchers ||= []
		@watchers << {
			paths:    paths,
			callback: blk,
		}
	end
end
