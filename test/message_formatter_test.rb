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

end

