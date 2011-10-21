require 'shellwords'
module Vmail
  class Query
    # args is an array like ARGV
    def self.parse(args)
      args = args.dup
      if args.is_a?(String)
        args = Shellwords.shellwords args
      end
      if args.size > 0 && args.first =~ /^\d+/
        args.shift
      end
      query = if args.empty?
                ['ALL']
              else
                args
              end
      query.map {|x| x.to_s.downcase}
    end

    def self.args2string(array)
      array.map {|x|
        x.to_s.split(/\s+/).size > 1 ? "\"#{x}\"" : x.to_s
      }.join(' ')
    end

  end
end
