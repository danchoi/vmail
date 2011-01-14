module Vmail
  module AddressQuoter

    def quote_addresses(input)
      parts = input.split /\s*,\s*/

      addrs = []
      savebin = ""

      #Group the parts together
      parts.each do |part|
        if part.include? "@"
          addrs << savebin + part
          savebin = ""
        else
          savebin = part + ", "
        end
      end
      
      #Quote the names
      addrs.map { |addr| addr.gsub(/^(.*) (<.*)/, '"\1" \2') }.join(', ')
    end
    
  end
end
