require 'drb'
#require File.expand_path("../gmail", __FILE__)
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'


class String
  def col(width)
    self[0,width].ljust(width)
  end
end


class GmailServer

  MailboxAliases = { 'sent' => '[Gmail]/Sent Mail',
    'all' => '[Gmail]/All Mail',
    'starred' => '[Gmail]/Starred',
    'important' => '[Gmail]/Important',
    'spam' => '[Gmail]/Spam',
    'trash' => '[Gmail]/Trash'
  }

  def initialize(config)
    @username, @password = config['login'], config['password']
    @mailbox = nil
  end

  def open
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    @imap.login(@username, @password)
  end

  def close
    @imap.close rescue Net::IMAP::BadResponseError
    @imap.disconnect
  end

  def select_mailbox(mailbox)
    if MailboxAliases[mailbox]
      mailbox = MailboxAliases[mailbox]
    end
    if mailbox == @mailbox 
      return
    end
    puts "selecting mailbox #{mailbox}"
    @imap.select(mailbox)
    @mailbox = mailbox
    return "OK"
  end

  def fetch_header(uid)
    results = @imap.uid_fetch(uid, ["FLAGS", "BODY", "ENVELOPE", "RFC822.HEADER"])
    res = results[0]
    header = res.attr["RFC822.HEADER"]
    mail = Mail.new(header)
    flags = res.attr["FLAGS"]
    puts "got data for #{uid}"
    "#{uid} #{format_time(mail.date.to_s)} #{mail.from[0][0,30].ljust(30)} #{mail.subject.to_s[0,70].ljust(70)} #{flags.inspect.col(30)}"
  end

  def search(num_messages, *query)
    query = query.join(' ')
    all_uids = @imap.uid_search(query)
    uids = all_uids[-([num_messages.to_i, all_uids.size].min)..-1] || []

    lines = []
    threads = []
    uids.each do |uid|

        sleep 0.1
        threads << Thread.new(uid) do |thread_uid|
          this_thread = Thread.current
          results = nil
          while results.nil?
            results = @imap.uid_fetch(thread_uid, ["FLAGS", "BODY", "ENVELOPE", "RFC822.HEADER"])
          end
          res = results[0]
          header = res.attr["RFC822.HEADER"]
          mail = Mail.new(header)
          mail_id = thread_uid
          flags = res.attr["FLAGS"]
          puts "got data for #{thread_uid}"
          "#{mail_id} #{format_time(mail.date.to_s)} #{mail.from[0][0,30].ljust(30)} #{mail.subject.to_s[0,70].ljust(70)} #{flags.inspect.col(30)}"
        end

    end
    threads.each {|t| lines << t.value}
    return lines.join("\n")
  rescue IOError
    open
    search(num_messages, query)
  end

  def lookup(uid, raw=false)
    puts "fetching #{uid.inspect}"
    res = @imap.uid_fetch(uid.to_i, ["FLAGS", "RFC822"])[0].attr["RFC822"]
    if raw
      return res
    end
    mail = Mail.new(res)
    out = nil
    if mail.parts.empty?
      out = [mail.header["Content-Type"], mail.body.charset, mail.body.decoded].join("\n")
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
      else 
        out = mail.parts.map {|part| part.inspect}.join("\n")
      end
    end
    out.gsub("\r", '')
  end


  def flag(uid, action, flg)
    # #<struct Net::IMAP::FetchData seqno=17423, attr={"FLAGS"=>[:Seen, "Flagged"], "UID"=>83113}>
    puts "flag #{uid} #{flg} #{action}"
    if flg == 'Deleted'
      @imap.uid_copy(uid.to_i, "[Gmail]/Trash")
      res = @imap.uid_store(uid.to_i, action, [flg.to_sym])
      "#{uid} deleted"
    else
      res = @imap.uid_store(uid.to_i, action, [flg.to_sym])
      fetch_header(uid.to_i)
    end
  end

  # TODO copy to a different mailbox

  # TODO mark spam

  private


  def puts(string)
    return # silent

  end

  def format_time(x)
    Time.parse(x.to_s).localtime.strftime "%D %I:%M%P"
  end

  def self.start
    config = YAML::load(File.read(File.expand_path("../../config/gmail.yml", __FILE__)))
    $gmail = GmailServer.new config
    $gmail.open
  end

  def self.daemon
    self.start
    $gmail.select_mailbox "inbox"

    url = "druby://127.0.0.1:61676"
    puts "starting gmail service at #{url}"
    DRb.start_service(url, $gmail)
    DRb.thread.join
  end
end

trap("INT") { 
  puts "closing connection"  
  $gmail.close
  exit
}

#GmailServer.daemon
__END__
GmailServer.start
$gmail.select_mailbox("inbox")

puts $gmail.flag(83113, "Flagged")
$gmail.close
