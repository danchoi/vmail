require 'test_helper'
require 'vmail/address_quoter'

class AddressQuoterTest < MiniTest::Unit::TestCase
  include Vmail::AddressQuoter

  def setup
    @string = "Bob Smith <bobsmith@gmail.com>, Jones, Rich A. <richjones@gmail.com>"
  end

  def test_quoting
    expected = '"Bob Smith" <bobsmith@gmail.com>, "Jones, Rich A." <richjones@gmail.com>'
    assert_equal expected, quote_addresses(@string)  #=> "Bob Smith" <bobsmith@gmail.com>, "Jones, Rich A." <richjones@gmail.com>
  end
end
