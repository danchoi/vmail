module Vmail
  class Query
    # args is an array like ARGV
    def self.parse(args)
      query = if args.empty? ? [100, 'ALL']
              elsif args.size == 1 && args[0] =~ /^\d+/ 
                [args.shift, "ALL"] 
              elsif args[0] =~ /^\d+/
                args
              else
                [100] + args
              end
      end

    end
  end
end
