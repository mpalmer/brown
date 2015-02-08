# -*- encoding: utf-8 -*-

require 'logger'

class Logger
	VERBOSE = 0.5
	TRACE   = -1

	# Lack of prior planning, peeps!
	remove_const(:SEV_LABEL)
	SEV_LABEL = {
		TRACE   => "TRACE",
		DEBUG   => "DEBUG",
		VERBOSE => "VERB",
		INFO    => "INFO",
		WARN    => "WARN",
		ERROR   => "ERROR",
		FATAL   => "FATAL"
	}

	def verbose(progname = nil, &block)
		add(VERBOSE, nil, progname, &block)
	end

	def trace(progname = nil, &block)
		add(TRACE, nil, progname, &block)
	end
end

module Brown::Logger
	def logger
		@logger ||= begin
			Logger.new($stderr).tap do |l|
				l.formatter = proc { |s,dt,n,msg| "#{$$} [#{s[0]}] #{msg}\n" }
				l.level = Logger.const_get(Brown.log_level.upcase.to_sym)
			end
		end
	end

	def log_level(level=nil)
		if level
			logger.level = Logger.const_get(level.upcase.to_sym)
		end
	end

	def backtrace(ex)
		if ex.respond_to?(:backtrace) and ex.backtrace
			self.debug { ex.backtrace.map { |l| "  #{l}" }.join("\n") }
		end
	end
end
