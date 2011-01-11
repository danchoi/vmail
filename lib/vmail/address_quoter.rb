module Vmail
  module AddressQuoter

    def quote_addresses(string)
      email_addrs = []
      string.scan(/\s*(.*?)\s*<(.+?)>(?:,|\Z)/) do |match|
        # yields ["Bob Smith", "bobsmith@gmail.com"]
        # then   ["Jones, Rich A.", "richjones@gmail.com"]
        email_addrs << "\"#{match.first}\" <#{match.last}>"
      end
      res = email_addrs.join(", ") 
      res
    end

  end
end
