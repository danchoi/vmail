require 'test_helper'

describe MessageFormatter do
  describe "when message has only an HTML body" do
    before do
      @raw = File.read(File.expand_path('../fixtures/htmlbody.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end

    it "should turn the body into readable text" do
      @formatter.process_body.must_match /\n   Web 1 new result for instantwatcher.com netflix/
    end
  end

  describe "euc-kr encoded mail" do
    before do
      @raw = File.read(File.expand_path('../fixtures/euc-kr-html.eml', __FILE__))
      @mail = Mail.new(@raw)
      @formatter = MessageFormatter.new(@mail)
    end

    it "should know its encoding" do
      puts @mail.header["Content-Type"]
      puts @mail.header.inspect
      #@mail.header['Content-Type'].must_equal "euc-kr"
    end

    it "should format the subject line in UTF-8" do
      @formatter.summary(123, [:Seen], "from").must_equal "test"
    end
  end
end

