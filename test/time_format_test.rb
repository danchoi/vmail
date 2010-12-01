require 'test_helper'
require 'time'

describe "TimeFormat methods" do
  before do
    @time_string = "2010-11-27T06:08:03-05:00"
    @time = Time.parse @time_string
  end

  it "should convert pacific to eastern" do
    string = "2010-11-27T06:08:03-08:00"
    time = Time.parse(string)
    time.to_s.must_equal "2010-11-27 09:08:03 -0500"
  end
end
