# encoding: utf-8
require 'test_helper'
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'vmail/reply_templating'
require 'vmail/message_formatter'

abort "test is outdated"

describe Vmail::ReplyTemplating do
  describe 'normal rfc822 message' do
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
      expected = {"from"=>"Daniel Choi <dhchoi@gmail.com>", "to"=>"Chappy Youn <chappy1@gmail.com>", "cc"=>"Draculette Ko <violinist.ko@gmail.com>, Cookiemonster Youn <cookiemonster@gmail.com>, Racoon <raycoon@gmail.com>", "subject"=>"Re: Holiday potluck at Ray's", :body=>"On Sun, Dec 12, 2010 at 01:13 PM, Chappy Youn <chappy1@gmail.com> wrote:\n\n> Guys,\n> Tonight we will have a potluck at Ray's at 7. Pls bring food for 1.5  \n> ppl.\n> \n> Ray will provide wine and dessert.\n> \n> Also, we will be having a poor man's Yankee swap. Pls bring something  \n> gift wrapped from home. Nothing fancy, but something halfway decent or  \n> funny.\n> \n> El, make sure it's worth more than 50 cents.\n> \n> Chappy\n> \n> Sent from my iPhone"}

      assert_equal expected,  @rt.reply_headers
    end
  end

  describe 'encoded rfc822 message' do
    before do
      @raw = read_fixture("reply-template-encoding-test.eml")
      @mail = Mail.new @raw
      @rt = Vmail::ReplyTemplate.new(@mail, 'dhchoi@gmail.com', 'Daniel Choi', true)
    end

    def test_encoded_header
      assert_equal '"björn" <bjorn.anon@gmail.com>', @rt.reply_headers['to']
    end
  end

end

