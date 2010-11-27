require 'net/imap'

class Gmail
  DEMARC = "------=gmail-tool="

  def initialize(username, password)
    @username, @password = username, password
  end

  def open
    raise "block missing" unless block_given?
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    @imap.login(@username, @password)
    yield @imap
  rescue Exception => ex
    raise
  ensure
    if @imap
      @imap.close rescue Net::IMAP::BadResponseError
      @imap.disconnect
    end
  end

  # lists mailboxes
  def mailboxes
    open do |imap|
      imap.list("[Gmail]/", "%") + imap.list("", "%")
    end
  end

  # selects the mailbox and returns self
  def mailbox(x)
    @mailbox = x
    # allow chaining
    return self 
  end

  def fetch(opts = {})
    num_messages = opts[:num_messages] || 10
    mailbox_label = opts[:mailbox] || @mailbox || 'inbox'
    query = opts[:query] || ["ALL"]
    open do |imap|
      imap.select(mailbox_label)
      all_uids = imap.uid_search(query)
      STDERR.puts "#{all_uids.size} UIDS TOTAL"
      uids = all_uids[-([num_messages, all_uids.size].min)..-1] || []
      STDERR.puts "imap process uids #{uids.inspect}"
      yield imap, uids
    end
  end

  # generic mailbox operations
  def imap
    open do |imap|
      imap.select((@mailbox || 'inbox'))
      yield imap
    end
  end
end


if __FILE__ == $0
  require 'yaml'
  require 'mail'
  config = YAML::load(File.read(File.expand_path("../../config/gmail.yml", __FILE__)))
  gmail = Gmail.new(config['login'], config['password'])
  mailbox = 'inbox'
  #query = ["BODY", "politics"]
  query = ARGV
  gmail.mailbox(mailbox).fetch(:num_messages => 30, :query => query) do |imap,uids|
    uids.each do |uid|
      res = imap.uid_fetch(uid, ["FLAGS", "BODY", "ENVELOPE", "RFC822.HEADER"])[0]
      #puts res.inspect
      #puts res
      header = res.attr["RFC822.HEADER"]
      mail = Mail.new(header)
      mail_id = "#{mailbox}:#{uid}"
      flags = res.attr["FLAGS"]
      puts "#{mail.date.to_s} #{mail.from[0][0,30].ljust(30)} #{mail.subject.to_s[0,70].ljust(70)} #{mail_id} #{flags.inspect}"
      #puts envelope.inspect
      next
      mail = Mail.new(res)
      foldline = [mail[:from], mail[:date], mail[:subject]].join(" ")
      puts foldline + " {{{1"
      if mail.parts.empty?
        puts mail.body.decoded
      else
        puts mail.parts.inspect
      end
    end
  end
end
