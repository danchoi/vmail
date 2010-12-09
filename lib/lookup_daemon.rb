require 'drb'
require File.expand_path("../message_formatter", __FILE__)
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'
require 'logger'

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
    'drafts' => '[Gmail]/Drafts',
    'spam' => '[Gmail]/Spam',
    'trash' => '[Gmail]/Trash'
  }

  attr_accessor :drb_uri
  def initialize(config)
    @username, @password = config['login'], config['password']
    @drb_uri = config['drb_uri']
    @mailbox = nil
    @logger = Logger.new(STDERR)
    @logger.level = Logger::DEBUG
  end

  def open
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    @imap.login(@username, @password)
  end

  def close
    log "closing connection"
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
    log "selecting mailbox #{mailbox.inspect}"
    reconnect_if_necessary do 
      @imap.select(mailbox)
    end
    @mailbox = mailbox
    @all_uids = []
    @bad_uids = []
    return "OK"
  end

  def revive_connection
    log "reviving connection"
    open
    log "reselecting mailbox #@mailbox"
    @imap.select(@mailbox)
  end

  def list_mailboxes
    @mailboxes ||= (@imap.list("[Gmail]/", "%") + @imap.list("", "%")).
      select {|struct| struct.attr.none? {|a| a == :Noselect} }.
      map {|struct| struct.name}.
      map {|name| MailboxAliases.invert[name] || name}
    @mailboxes.delete("INBOX")
    @mailboxes.unshift("INBOX")
    @mailboxes.join("\n")
  end

  def fetch_headers(uid_set)
    if uid_set.is_a?(String)
      uid_set = uid_set.split(",").map(&:to_i)
    elsif uid_set.is_a?(Integer)
      uid_set = [uid_set]
    end
    log "fetch headers for #{uid_set.inspect}"
    if uid_set.empty?
      log "empty set"
      return ""
    end
    results = reconnect_if_necessary do 
      @imap.uid_fetch(uid_set, ["FLAGS", "ENVELOPE"])
    end
    log "extracting headers"
    lines = results.map do |res|
      format_header(res)
    end
    log "returning result" 
    return lines.join("\n")
  end

  def format_header(fetch_data)
    uid = fetch_data.attr["UID"]
    envelope = fetch_data.attr["ENVELOPE"]
    flags = fetch_data.attr["FLAGS"]
    address_struct = (@mailbox == '[Gmail]/Sent Mail' ? envelope.to.first : envelope.from.first)
    
    address = [address_struct.mailbox, address_struct.host].join('@') 
    if address_struct.name
      address = "#{address_struct.name} <#{address}>"
    end
    date = Time.parse(envelope.date).localtime.strftime "%b %d %I:%M%P" rescue envelope.date.to_s 
    flags = format_flags(flags)
    "#{uid} #{(date || '').ljust(14)} #{address[0,30].ljust(30)} #{(envelope.subject || '').encode('utf-8')[0,70].ljust(70)} #{flags.col(30)}"
  end

  FLAGMAP = {:Flagged => '[*]'}
  # flags is an array like [:Flagged, :Seen]
  def format_flags(flags)
    flags = flags.map {|flag| FLAGMAP[flag] || flag}
    if flags.delete(:Seen).nil?
      flags << '[+]' # unread
    end
    flags.join('')
  end

  def search(limit, *query)
    log "uid_search limit: #{limit} query: #{@query.inspect}"
    limit = 25 if limit.to_s !~ /^\d+$/
    query = ['ALL'] if query.empty?
    @query = query.join(' ')
    log "uid_search #@query #{limit}"
    @all_uids = reconnect_if_necessary do
      @imap.uid_search(@query)
    end
    uids = @all_uids[-([limit.to_i, @all_uids.size].min)..-1] || []
    res = fetch_headers(uids)
    add_more_message_line(res, uids)
  end

  def update
    reconnect_if_necessary(4) do 
      # this is just to prime the IMAP connection
      # It's necessary for some reason.
      fetch_headers(@all_uids[-1])
      log "test"
    end
    uids = reconnect_if_necessary { 
      log "uid_search #@query"
      @imap.uid_search(@query) 
    }
    new_uids = uids - @all_uids
    log "UPDATE: NEW UIDS: #{new_uids.inspect}"
    if !new_uids.empty?
      res = fetch_headers(new_uids)
      @all_uids = uids
      res
    end
  end

  # gets 100 messages prior to uid
  def more_messages(uid, limit=100)
    uid = uid.to_i
    x = [(@all_uids.index(uid) - limit), 0].max
    y = [@all_uids.index(uid) - 1, 0].max
    uids = @all_uids[x..y]
    res = fetch_headers(uids)
    add_more_message_line(res, uids)
  end

  def add_more_message_line(res, uids)
    return res if uids.empty?
    start_index = @all_uids.index(uids[0])
    if start_index > 0
      remaining = start_index 
      res = "> Load #{[100, remaining].min} more messages. #{remaining} remaining.\n" + res
    end
    res 
  end

  def lookup(uid, raw=false)
    log "fetching #{uid.inspect}"
    res = reconnect_if_necessary do 
      @imap.uid_fetch(uid.to_i, ["FLAGS", "RFC822"])[0].attr["RFC822"]
    end
    if raw
      return res
    end
    mail = Mail.new(res)
    formatter = MessageFormatter.new(mail)
    part = formatter.find_text_part

    out = formatter.process_body 
    message = <<-END
#{format_headers(formatter.extract_headers)}

#{formatter.list_parts}

-- body --

#{out}
END
  end

  def flag(uid_set, action, flg)
    uid_set = uid_set.split(",").map(&:to_i)
    # #<struct Net::IMAP::FetchData seqno=17423, attr={"FLAGS"=>[:Seen, "Flagged"], "UID"=>83113}>
    log "flag #{uid_set} #{flg} #{action}"
    if flg == 'Deleted'
      # for delete, do in a separate thread because deletions are slow
      Thread.new do 
        @imap.uid_copy(uid_set, "[Gmail]/Trash")
        res = @imap.uid_store(uid_set, action, [flg.to_sym])
      end
      uid_set.each { |uid| @all_uids.delete(uid) }
    elsif flg == '[Gmail]/Spam'
      @imap.uid_copy(uid_set, "[Gmail]/Spam")
      res = @imap.uid_store(uid_set, action, [:Deleted])
      "#{uid} deleted"
    else
      log "Flagging"
      res = @imap.uid_store(uid_set, action, [flg.to_sym])
      # log res.inspect
      fetch_headers(uid_set)
    end
  end

  # TODO copy to a different mailbox

  # TODO mark spam

  def message_template
    headers = {'from' => @username,
      'to' => 'dhchoi@gmail.com',
      'subject' => "test #{rand(90)}"
    }
    format_headers(headers) + "\n\n"
  end

  def format_headers(hash)
    lines = []
    hash.each_pair do |key, value|
      if value.is_a?(Array)
        value = value.join(", ")
      end
      lines << "#{key}: #{value}"
    end
    lines.join("\n")
  end

  def reply_template(uid, replyall=false)
    res = @imap.uid_fetch(uid.to_i, ["FLAGS", "RFC822"])[0].attr["RFC822"]
    mail = Mail.new(res)
    formatter = MessageFormatter.new(mail)
    headers = formatter.extract_headers
    reply_to = headers['reply_to'] || headers['from']
    sender = headers['from']
    subject = headers['subject']
    if subject !~ /Re: /
      subject = "Re: #{subject}"
    end
    cc = replyall ? mail['cc'] : nil
    #cc = [cc, headers['to']].join(', ')
    # orig message info e.g.
    # On Wed, Dec 1, 2010 at 3:30 PM, Matt MacDonald (JIRA) <do-not-reply@prx.org> wrote:
    # quoting
    # quote header
    #date = Time.parse(headers['date'].to_s)
    date = headers['date']
    quote_header = "On #{date.strftime('%a, %b %d, %Y at %I:%M %p')}, #{sender} wrote:\n\n"

    # TODO fix the character encoding, making sure it is valid UTF8 and encoded as such 
    body = quote_header + formatter.process_body.gsub(/^(?=>)/, ">").gsub(/^(?!>)/, "> ")

    reply_headers = { 'from' => @username, 'to' => reply_to, 'cc' => cc, 'subject' => headers['subject']}
    format_headers(reply_headers) + "\n\n" + body
  end

  def deliver(text)
    # parse the text. The headers are yaml. The rest is text body.
    require 'net/smtp'
    require 'smtp_tls'
    require 'mail'
    mail = Mail.new
    raw_headers, body = *text.split(/\n\n/, 2)
    headers = {}
    raw_headers.split("\n").each do |line|
      key, value = *line.split(':', 2)
      headers[key] = value
    end
    log "headers: #{headers.inspect}"
    log "delivering: #{headers.inspect}"
    mail.from = headers['from'] || @username
    mail.to = headers['to'] #.split(/,\s+/)
    mail.cc = headers['cc'] #&& headers['cc'].split(/,\s+/)
    mail.bcc = headers['bcc'] #&& headers['cc'].split(/,\s+/)
    mail.subject = headers['subject']
    mail.delivery_method(*smtp_settings)
    mail.from ||= @username
    mail.body = body
    mail.deliver!
    "SENT"
  end
 
  def smtp_settings
    [:smtp, {:address => "smtp.gmail.com",
    :port => 587,
    :domain => 'gmail.com',
    :user_name => @username,
    :password => @password,
    :authentication => 'plain',
    :enable_starttls_auto => true}]
  end

  def log(string)
    @logger.debug string
  end

  def handle_error(error)
    log error
  end

  def reconnect_if_necessary(timeout = 60, &block)
    # if this times out, we know the connection is stale while the user is trying to update
    Timeout::timeout(timeout) do
      block.call
    end
  rescue IOError, Errno::EADDRNOTAVAIL, Timeout::Error
    log "error: #{$!}"
    log "attempting to reconnect"
    log(revive_connection)
    # try just once
    block.call
  end

  def self.start
    config = YAML::load(File.read(File.expand_path("../../config/gmail.yml", __FILE__)))
    $gmail = GmailServer.new config
    $gmail.open
  end

  def self.daemon
    self.start
    puts DRb.start_service($gmail.drb_uri, $gmail)
    uri = DRb.uri
    puts "starting gmail service at #{uri}"
    uri
    DRb.thread.join
  end

end

trap("INT") { 
  require 'timeout'
  puts "closing connection"  
  begin
    Timeout::timeout(5) do 
      $gmail.close
    end
  rescue Timeout::Error
    puts "close connection attempt timed out"
  end
  exit
}

if __FILE__ == $0
  puts "starting gmail server"
  GmailServer.daemon
end
