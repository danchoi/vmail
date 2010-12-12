require 'test_helper'

describe "Decode base64 string" do
  before do
    @string = "=?GB2312?B?Rnc6IEVsZWN0cm9uaWMgUGlja3BvY2tldGluZyDQodDE0MXTw7+o?="
  end

  it "should decode" do
    skip
    require 'base64'
    assert_equal 'test', Base64::decode64(@string)
  end
end
