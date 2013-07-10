gem "minitest"
require 'minitest/autorun'
require 'vmail/version'
require 'vmail/options'
require 'vmail/inbox_poller'

describe Vmail::InboxPoller do
  before do
    working_dir = ENV['VMAIL_HOME'] || "#{ENV['HOME']}/.vmail/default"
    Dir.chdir(working_dir)
    opts = Vmail::Options.new(["--config", ".vmailrc"])
    opts.config
    config = opts.config
    @inbox_poller = Vmail::InboxPoller.start config
    @notifier = @inbox_poller.initialize_notifier
  end

  after do
    @inbox_poller.close
  end

  describe "test notifications" do
    it "does not fail" do
      @notifier.call "This is a simple notification title", "This is a simple body"
    end
  end

  describe "when a notification contains single quotes" do
    it "does not fail" do
      res = @notifier.call "Someone's notification", "Shouldn't fail with single quotes"

      print "res: #{res}"
    end
  end
end
