require 'vmail/options'
require 'vmail/imap_client'

module Vmail
  module Sender
    extend self

    def send
      opts = Vmail::Options.new(ARGV)
      config = opts.config.merge 'logile' => STDERR
      imap_client = Vmail::ImapClient.new config
      imap_client.deliver STDIN.read
    end
  end
end

