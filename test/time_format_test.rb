require 'test_helper'
require 'time'

class TimeFormatTest < MiniTest::Unit::TestCase
  def setup
    @time_string = "2010-11-27T06:08:03-05:00"
    @time = Time.parse @time_string
  end

  def test_convert_local
    string = "2010-11-27T06:08:03-08:00"
    time = Time.parse(string)
    puts "TEST"
    puts time.localtime
  end
end
