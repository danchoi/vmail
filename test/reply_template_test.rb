require 'test_helper'
require 'vmail/reply_template'

describe Vmail::ReplyTemplate do
  before do
    @raw = read_fixture('reply_all.eml')
    @mail = Mail.new(@raw)
    @rt = Vmail::ReplyTemplate.new(@mail, 'dhchoi@gmail.com', 'Daniel Choi', true)
  end

  def test_detect_primary_recipient
    assert_equal "Chappy Youn <chappy1@gmail.com>", @rt.primary_recipient
  end

  def test_detect_cc
    expected = "Draculette Ko <violinist.ko@gmail.com>, Cookiemonster Youn <cookiemonster@gmail.com>, Racoon <raycoon@gmail.com>"
    assert_equal expected, @rt.cc
  end
  
  def test_sender
    assert_equal "Chappy Youn <chappy1@gmail.com>", @rt.sender
  end

  def test_template
    expected = {"from"=>"Daniel Choi <dhchoi@gmail.com>", "to"=>"Chappy Youn <chappy1@gmail.com>", "cc"=>"Draculette Ko <violinist.ko@gmail.com>, Cookiemonster Youn <cookiemonster@gmail.com>, Racoon <raycoon@gmail.com>", "subject"=>"Re: Holiday potluck at Ray's"}
    assert_equal expected,  @rt.reply_headers
  end


end

