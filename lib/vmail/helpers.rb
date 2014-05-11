module Vmail
  DIVIDER_WIDTH = 46
  UNITS = [:b, :k, :M, :G].freeze

  module Helpers

    def retry_if_needed
      res = nil
      3.times do
        res = yield
        break if res
      end
      res
    end

    # borrowed from ActionView/Helpers
    def number_to_human_size(number)
      if number.to_i < 1024
        "< 1k" # round up to 1kh
      else
        max_exp = UNITS.size - 1
        exponent = (Math.log(number) / Math.log(1024)).to_i # Convert to base 1024
        exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
        number  /= 1024 ** exponent
        unit = UNITS[exponent]
        "#{number}#{unit}"
      end
    end


    def divider(str)
      str * DIVIDER_WIDTH
    end


  end
end
