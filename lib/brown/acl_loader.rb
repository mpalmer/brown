# -*- encoding: utf-8 -*-

require 'tmpdir'
require 'protobuf'

require "brown/logger"

class Brown::ACLLoader
	extend Brown::Logger

	def self.load_all(*dirs)
		dirs.flatten!
		pfiles = dirs.each_with_object([]) do |dir, list|
			list << Dir["#{dir}/*.proto"]
		end.flatten

		load_proto_files(pfiles, dirs)
	end

	def self.load_proto_files(pfiles, dirs)
		orig_load_path = $LOAD_PATH

		Dir.mktmpdir do |tmpdir|
			dirs = pfiles.map { |f| File.dirname(f) }.uniq + [tmpdir]
			dirs.each { |d| $LOAD_PATH.unshift(d) }

			compiles = []

			pfiles.each do |f|
				pbrbfile = f.gsub(/\.proto$/, ".pb.rb")
				unless File.exists?(pbrbfile) and File.stat(pfile).mtime <= File.stat(pbrbfile).mtime
					compiles << f
				end
			end

			includes = dirs.map { |d| "-I '#{d}'" }.join(" ")

			unless compiles.empty?
				cmd = "protoc --ruby_out='#{tmpdir}' #{includes} #{compiles.map { |f| "'#{f}'" }.join(' ')} 2>&1"
				output = nil

				IO.popen(cmd) { |fd| output = fd.read }

				if $?.exitstatus != 0
					logger.fatal { "protoc failed: #{output}" }
					raise RuntimeError, output
				end
			end

			pfiles.each do |f|
				require "#{File.basename(f, '.proto')}.pb"
			end
		end
	ensure
		$LOAD_PATH.replace(orig_load_path)
	end
end
