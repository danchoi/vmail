# encoding: utf-8
require 'test_helper'

describe MessageFormatter do
  describe "message with email addresses along with names" do
    before do
      @raw = File.read(File.expand_path('../fixtures/google-affiliate.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end

    it "should extract name along with email address" do
      expected = '"Google Affiliate Network" <affiliatenetwork@google.com>'
      @formatter.extract_headers['from'].must_equal 'Google Affiliate Network <affiliatenetwork@google.com>'
      @formatter.extract_headers['to'].must_match 'Dan Choi <dhchoi@gmail.com>'
      @formatter.extract_headers['cc'].must_match 'Steve Jobs <steve@apple.com>'
    end
  end

  describe "message has a text body but no Content-Type" do
    before do 
      @raw = File.read(File.expand_path('../fixtures/textbody-nocontenttype.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end
    it "should return the text body" do
      @formatter.process_body.wont_be_nil
      @formatter.process_body.must_match /Friday the 13th/
    end
  end

  describe "when message has only an HTML body" do
    before do
      @raw = File.read(File.expand_path('../fixtures/htmlbody.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end
    it "should turn the body into readable text" do
      @formatter.process_body.must_match %r{\n   Web 1 new result for instantwatcher.com netflix}
    end
  end

  describe "euc-kr encoded header" do
    before do
      @raw = File.read(File.expand_path('../fixtures/euc-kr-header.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end
    it "should know its encoding" do
      @mail.header.charset.must_equal 'euc-kr'
    end
    it "should format the subject line in UTF-8" do
      match = "독특닷컴과"
      assert_match match, @formatter.extract_headers['subject'] 
    end
  end

  describe "when message has only an HTML body and no encoding info" do
    before do 
      @raw = File.read(File.expand_path('../fixtures/moleskine-html.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end
    it "should process body" do
      @formatter.process_body.wont_be_nil
    end
  end

end

