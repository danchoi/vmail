require 'drb'
#require File.expand_path("../gmail", __FILE__)
require 'yaml'
require 'mail'
require 'net/imap'

class GmailServer
  def initialize(config)
    @username, @password = config['login'], config['password']
  end

  def open
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    @imap.login(@username, @password)
  end

  def close
    @imap.close rescue Net::IMAP::BadResponseError
    @imap.disconnect
  end

  def select(mailbox)
    @imap.select(mailbox)
  end

  def lookup(uid, raw=false)
    res = @imap.uid_fetch(uid.to_i, ["FLAGS", "RFC822"])[0].attr["RFC822"]
    if raw
      return res
    end
    mail =  Mail.new(res)
    out = nil
    if mail.parts.empty?
      out = [ mail.header["Content-Type"], 
        mail.body.charset,
        mail.body.decoded ].join("\n")
    else
      part = mail.parts.detect {|part| 
        (part.header["Content-Type"].to_s =~ /text\/plain/)
      }
      if part
        out = [  mail.parts.inspect,
        "PART",
        part.header["Content-Type"],
        part.charset,
        part.body.decoded].join("\n")
      end
    end
    out.gsub("\r", '')
  end
end

config = YAML::load(File.read(File.expand_path("../../config/gmail.yml", __FILE__)))
gmail = GmailServer.new config
gmail.open
gmail.select "inbox"

url = "druby://127.0.0.1:61676"
puts "starting gmail service at #{url}"
DRb.start_service(url, gmail)
trap("INT") { 
  puts "closing connection"  
  gmail.close
  exit
}
DRb.thread.join

