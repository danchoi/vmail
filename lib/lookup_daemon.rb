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

  def rcol(width) #right justified
    self[0,width].rjust(width)
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
    @name = config['name']
    @signature = config['signature']
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
    lines = results.sort_by {|x| Time.parse(x.attr['ENVELOPE'].date)}.map {|x| format_header(x)}
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
    date = Time.parse(envelope.date).localtime
    date_formatted = if date.year != Time.now.year
                       date.strftime "%b %d %Y" rescue envelope.date.to_s 
                     else 
                       date.strftime "%b %d %I:%M%P" rescue envelope.date.to_s 
                     end
    flags = format_flags(flags)
    first_col_width = @all_uids.max.to_s.length 
    mid_width = @width - (first_col_width + 14 + 2) - (10 + 2) - 2
    address_col_width = (mid_width * 0.3).ceil
    subject_col_width = (mid_width * 0.7).floor
    "#{uid.to_s.col(first_col_width)} #{(date_formatted || '').col(14)} #{address.col(address_col_width)} #{(envelope.subject || '').encode('utf-8').col(subject_col_width)} #{flags.rcol(10)}"
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

  def lookup(uid, raw=false, forwarded=false)
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

#{forwarded ? nil : formatter.list_parts}
#{out}
END
  end

  # uid_set is a string comming from the vim client
  # action is -FLAGS or +FLAGS
  def flag(uid_set, action, flg)
    if uid_set.is_a?(String)
      uid_set = uid_set.split(",").map(&:to_i)
    end
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

  # uid_set is a string comming from the vim client
  def move_to(uid_set, mailbox)
    if MailboxAliases[mailbox]
      mailbox = MailboxAliases[mailbox]
    end
    log "move_to #{uid_set.inspect} #{mailbox}"
    if uid_set.is_a?(String)
      uid_set = uid_set.split(",").map(&:to_i)
    end
    log @imap.uid_copy(uid_set, mailbox)
    log @imap.uid_store(uid_set, '+FLAGS', [:Deleted])
  end

  # TODO mark spam

  def new_message_template
    headers = {'from' => "#{@name} <#{@username}>",
      'to' => nil,
      'subject' => nil
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
    fetch_data = @imap.uid_fetch(uid.to_i, ["FLAGS", "ENVELOPE", "RFC822"])[0]
    envelope = fetch_data.attr['ENVELOPE']
    recipients = if replyall
                    [envelope.from, envelope.to, envelope.cc, envelope.reply_to].flatten.
                      uniq.
                      compact.
                      select {|x| "#{x.mailbox}@#{x.host}" != @username}.
                      map {|x| 
                        x.name ? "#{x.name} <#{x.mailbox}@#{x.host}>" : "#{x.mailbox}@#{x.host}"
                      }.join(", ")
                 else
                   x = (envelope.reply_to || envelope.from)[0]
                   x.name ? "#{x.name} <#{x.mailbox}@#{x.host}>" : "#{x.mailbox}@#{x.host}"
                 end
    mail = Mail.new fetch_data.attr['RFC822']
    formatter = MessageFormatter.new(mail)
    headers = formatter.extract_headers
    sender = headers['from']
    subject = headers['subject']
    if subject !~ /Re: /
      subject = "Re: #{subject}"
    end
    cc = replyall ? mail['cc'] : nil
    date = headers['date'].is_a?(String) ? Time.parse(headers['date']) : headers['date']
    quote_header = "On #{date.strftime('%a, %b %d, %Y at %I:%M %p')}, #{sender} wrote:\n\n"
    body = quote_header + formatter.process_body.gsub(/^(?=>)/, ">").gsub(/^(?!>)/, "> ")
    reply_headers = { 'from' => "#@name <#@username>", 'to' => recipients, 'cc' => cc, 'subject' => headers['subject']}
    format_headers(reply_headers) + "\n\n" + body + signature
  end

  def signature
    return '' unless @signature
    "\n\n#@signature"
  end

  # TODO, forward with attachments 
  def forward_template(uid)
    original_body = lookup(uid, false, true)
    new_message_template + 
      "\n---------- Forwarded message ----------\n" +
      original_body + signature
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

  def window_width=(width)
    log "setting window width to #{width}"
    @width = width.to_i
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
