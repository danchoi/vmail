require 'shellwords'
module Vmail
  class Query
    # args is an array like ARGV
    def self.parse(args)
      if args.is_a?(String)
        args = Shellwords.shellwords args
      end
      query = if args.empty? 
                [100, 'ALL']
              elsif args.size == 1 && args[0] =~ /^\d+/ 
                [args.shift, "ALL"] 
              elsif args[0] =~ /^\d+/
                args
              else
                [100] + args
              end
      query
    end

    def self.args2string(array)
      array.map {|x|
        x.to_s.split(/\s+/).size > 1 ? "\"#{x}\"" : x.to_s
      }.join(' ')
    end

  end
end
