# encoding: UTF-8
require 'drb'
require 'vmail/string_ext'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'
require 'logger'
require 'vmail/helpers'
require 'vmail/address_quoter'
require 'vmail/database'
require 'vmail/searching'
require 'vmail/showing_headers'
require 'vmail/showing_message'
require 'vmail/flagging_and_moving'

module Vmail
  class ImapClient
    include Vmail::Helpers
    include Vmail::AddressQuoter
    include Vmail::Searching
    include Vmail::ShowingHeaders
    include Vmail::ShowingMessage
    include Vmail::FlaggingAndMoving

    attr_accessor :max_seqno # of current mailbox

    def initialize(config)
      @username, @password = config['username'], config['password']
      @name = config['name']
      @signature = config['signature']
      @always_cc = config['always_cc']
      @mailbox = nil
      @logger = Logger.new(config['logfile'] || STDERR)
      @logger.level = Logger::DEBUG
      @imap_server = config['server'] || 'imap.gmail.com'
      @imap_port = config['port'] || 993
      current_message = nil
    end


    def open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      log @imap.login(@username, @password)
      list_mailboxes # prefetch mailbox list
    end

    # expects a block, closes on finish
    def with_open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      log @imap.login(@username, @password)
      yield self
      close
    end

    def close
      log "Closing connection"
      Timeout::timeout(10) do
        @imap.close rescue Net::IMAP::BadResponseError
        @imap.disconnect rescue IOError
      end
    rescue Timeout::Error
    end

    def select_mailbox(mailbox, force=false)
      if mailbox_aliases[mailbox]
        mailbox = mailbox_aliases[mailbox]
      end
      log "Selecting mailbox #{mailbox.inspect}"
      reconnect_if_necessary(15) do 
        log @imap.select(mailbox)
      end
      log "Done"

      @mailbox = mailbox
      @label = Label[name: @mailbox] || Label.create(name: @mailbox)

      log "Getting mailbox status"
      get_mailbox_status
      log "Getting highest message id"
      get_highest_message_id
      if @next_window_width
        @width = @next_window_width
      end

      return "OK"
    end

    def reload_mailbox
      return unless STDIN.tty?
      select_mailbox(@mailbox, true)
    end

    # TODO no need for this if all shown messages are stored in SQLITE3 
    # and keyed by UID.
    def clear_cached_message
      return unless STDIN.tty?
      log "Clearing cached message"
      current_message = nil
    end

    def get_highest_message_id
      # get highest message ID
      res = @imap.fetch([1,"*"], ["ENVELOPE"])
      if res 
        @num_messages = res[-1].seqno
        log "Highest seqno: #@num_messages"
      else
        @num_messages = 1
        log "NO HIGHEST ID: setting @num_messages to 1"
      end
    end

    # not used for anything
    def get_mailbox_status
      return
      @status = @imap.status(@mailbox,  ["MESSAGES", "RECENT", "UNSEEN"])
      log "Mailbox status: #{@status.inspect}"
    end

    def revive_connection
      log "Reviving connection"
      open
      log "Reselecting mailbox #@mailbox"
      @imap.select(@mailbox)
    end

    def prime_connection
      return if @ids.nil? || @ids.empty?
      reconnect_if_necessary(4) do 
        # this is just to prime the IMAP connection
        # It's necessary for some reason before update and deliver. 
        log "Priming connection"
        res = @imap.fetch(@ids[-1], ["ENVELOPE"])
        if res.nil?
          # just go ahead, just log
          log "Priming connection didn't work, connection seems broken, but still going ahead..."
        end
      end 
    end

    def list_mailboxes
      log 'loading mailboxes...'
      @mailboxes ||= (@imap.list("", "*") || []).
        select {|struct| struct.attr.none? {|a| a == :Noselect} }.
        map {|struct| struct.name}.uniq
      @mailboxes.delete("INBOX")
      @mailboxes.unshift("INBOX")
      log "Loaded mailboxes: #{@mailboxes.inspect}"
      @mailboxes = @mailboxes.map {|name| mailbox_aliases.invert[name] || name}
      @mailboxes.join("\n")
    end

    # do this just once
    def mailbox_aliases
      return @mailbox_aliases if @mailbox_aliases
      aliases = {"sent" => "Sent Mail",
                 "all" => "All Mail",
                 "starred" => "Starred",
                 "important" => "Important",
                 "drafts" => "Drafts",
                 "spam" => "Spam",
                 "trash" => "Trash"}
      @mailbox_aliases = {}
      aliases.each do |shortname, fullname|
        [ "[Gmail]", "[Google Mail" ].each do |prefix|
          if self.mailboxes.include?( "#{prefix}/#{fullname}" )
            @mailbox_aliases[shortname] =  "#{prefix}/#{fullname}"
          end
        end
      end
      log "Setting aliases to #{@mailbox_aliases.inspect}"
      @mailbox_aliases
    end

    # called internally, not by vim client
    def mailboxes
      if @mailboxes.nil?
        list_mailboxes
      end
      @mailboxes
    end

    def decrement_max_seqno(num)
      return unless STDIN.tty?
      log "Decremented max seqno from #{self.max_seqno} to #{self.max_seqno - num}"
      self.max_seqno -= num
    end

    # TODO why not just reload the current page?
    def update
      if search_query?
        log "Update aborted because query is search query: #{@query.inspect}"
        return ""
      end
      prime_connection
      old_num_messages = @num_messages
      # we need to re-select the mailbox to get the new highest id
      reload_mailbox
      update_query = @query.dup
      # set a new range filter
      # this may generate a negative rane, e.g., "19893:19992" but that seems harmless
      update_query[0] = "#{old_num_messages}:#{@num_messages}"
      ids = reconnect_if_necessary { 
        log "Search #update_query"
        @imap.search(Vmail::Query.args2string(update_query))
      }
      log "- got seqnos: #{ids.inspect}"
      log "- getting seqnos > #{self.max_seqno}"
      new_ids = ids.select {|seqno| seqno > self.max_seqno}
      @ids = @ids + new_ids
      log "- update: new uids: #{new_ids.inspect}"
      if !new_ids.empty?
        self.max_seqno = new_ids[-1]
        res = get_message_headers(new_ids.reverse)
        res
      else
        ''
      end
    end

    # gets 100 messages prior to id
    def more_messages
      log "Getting more_messages"
      x = [(@start_index - @limit), 0].max
      y = [@start_index - 1, 0].max
      @start_index = x
      fetch_ids = search_query? ? @ids[x..y] : (x..y).to_a
      message_ids = fetch_and_cache_headers(fetch_ids)
      res = get_message_headers message_ids
      with_more_message_line(res)
    end

    def spawn_thread_if_tty(&block) 
      if STDIN.tty?
        Thread.new do 
          reconnect_if_necessary(10, &block)
        end
      else
        block.call
      end
    end

    def create_if_necessary(mailbox)
      current_mailboxes = mailboxes.map {|m| mailbox_aliases[m] || m}
      if !current_mailboxes.include?(mailbox)
        log "Current mailboxes: #{current_mailboxes.inspect}"
        log "Creating mailbox #{mailbox}"
        log @imap.create(mailbox) 
        @mailboxes = nil # force reload ...
        list_mailboxes
      end
    end

    def append_to_file(uid_set, file)
      uid_set = uid_set.split(',').map(&:to_i)
      log "Append to file uid set #{uid_set.inspect} to file: #{file}"
      uid_set.each do |uid|
        message = show_message(uid)
        File.open(file, 'a') {|f| f.puts(divider('=') + "\n" + message + "\n\n")}
        subject = (message[/^subject:(.*)/,1] || '').strip
        log "Appended message '#{subject}'"
      end
      "Printed #{uid_set.size} message#{uid_set.size == 1 ? '' : 's'} to #{file.strip}"
    end

    def new_message_template(subject = nil, append_signature = true)
      headers = {'from' => "#{@name} <#{@username}>",
        'to' => nil,
        'subject' => subject,
        'cc' => @always_cc 
      }
      format_headers(headers) + (append_signature ? ("\n\n" + signature) : "\n\n")
    end

    def format_headers(hash)
      lines = []
      hash.each_pair do |key, value|
        if value.is_a?(Array)
          value = value.join(", ")
        end
        lines << "#{key.gsub("_", '-')}: #{value}"
      end
      lines.join("\n")
    end

    def reply_template(replyall=false)
      log "Sending reply template"
      reply_headers = Vmail::ReplyTemplate.new(current_message.rfc822, @username, @name, replyall, @always_cc).reply_headers
      body = reply_headers.delete(:body)
      format_headers(reply_headers) + "\n\n\n" + body + signature
    end

    def signature
      return '' unless @signature
      "\n\n#@signature"
    end

    def forward_template
      original_body = current_message.plaintext.split(/\n-{20,}\n/, 2)[1]
      formatter = Vmail::MessageFormatter.new(current_mail)
      headers = formatter.extract_headers
      subject = headers['subject']
      if subject !~ /Fwd: /
        subject = "Fwd: #{subject}"
      end

      new_message_template(subject, false) + 
        "\n---------- Forwarded message ----------\n" +
        original_body + signature
    end

    def format_sent_message(mail)
      formatter = Vmail::MessageFormatter.new(mail)
      message_text = <<-EOF
Sent Message #{self.format_parts_info(formatter.list_parts)}

#{format_headers(formatter.extract_headers)}

#{formatter.plaintext_part}
EOF
    end

    def deliver(text)
      # parse the text. The headers are yaml. The rest is text body.
      require 'net/smtp'
      # prime_connection
      mail = new_mail_from_input(text)
      mail.delivery_method(*smtp_settings)
      res = mail.deliver!
      log res.inspect
      log "\n"
      msg = if res.is_a?(Mail::Message)
        "Message '#{mail.subject}' sent"
      else
        "Failed to deliver message '#{mail.subject}'!"
      end
      log msg
      msg
    end

    def new_mail_from_input(text)
      require 'mail'
      mail = Mail.new
      raw_headers, raw_body = *text.split(/\n\s*\n/, 2)
      headers = {}
      raw_headers.split("\n").each do |line|
        key, value = *line.split(/:\s*/, 2)
        log [key, value].join(':')
        if %w(from to cc bcc).include?(key)
          value = quote_addresses(value)
        end
        headers[key] = value
      end
      log "Delivering message with headers: #{headers.to_yaml}"
      mail.from = headers['from'] || @username
      mail.to = headers['to'] #.split(/,\s+/)
      mail.cc = headers['cc'] #&& headers['cc'].split(/,\s+/)
      mail.bcc = headers['bcc'] #&& headers['cc'].split(/,\s+/)
      mail.subject = headers['subject']
      mail.from ||= @username
      # attachments are added as a snippet of YAML after a blank line
      # after the headers, and followed by a blank line
      if (attachments = raw_body.split(/\n\s*\n/, 2)[0]) =~ /^attach(ment|ments)*:/
        files = YAML::load(attachments).values.flatten
        log "Attach: #{files}"
        files.each do |file|
          if File.directory?(file)
            Dir.glob("#{file}/*").each {|f| mail.add_file(f) if File.size?(f)}
          else
            mail.add_file(file) if File.size?(file)
          end
        end
        mail.text_part do
          body raw_body.split(/\n\s*\n/, 2)[1]
        end

      else
        mail.text_part do
          body raw_body
        end
      end
      mail
    end

    def save_attachments(dir)
      log "Save_attachments #{dir}"
      if !current_mail
        log "Missing a current message"
      end
      return unless dir && current_mail
      attachments = current_mail.attachments
      `mkdir -p #{dir}`
      saved = attachments.map do |x|
        path = File.join(dir, x.filename)
        log "Saving #{path}"
        File.open(path, 'wb') {|f| f.puts x.decoded}
        path
      end
      "Saved:\n" + saved.map {|x| "- #{x}"}.join("\n")
    end

    def open_html_part
      log "Open_html_part"
      log current_mail.parts.inspect
      multipart = current_mail.parts.detect {|part| part.multipart?}
      html_part = if multipart 
                    multipart.parts.detect {|part| part.header["Content-Type"].to_s =~ /text\/html/}
                  elsif ! current_mail.parts.empty?
                    current_mail.parts.detect {|part| part.header["Content-Type"].to_s =~ /text\/html/}
                  else
                    current_mail.body
                  end
      return if html_part.nil?
      outfile = 'part.html'
      File.open(outfile, 'w') {|f| f.puts(html_part.decoded)}
      # client should handle opening the html file
      return outfile
    end

    def window_width=(width)
      @next_window_width = width.to_i
      if @width.nil?
        @width = @next_window_width
      end
      log "Setting next window width to #{width}"
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
      # if this times out, we know the connection is stale while the user is
      # trying to update
      Timeout::timeout(timeout) do
        block.call
      end
    rescue IOError, Errno::EADDRNOTAVAIL, Errno::ECONNRESET, Timeout::Error
      log "Error: #{$!}"
      log "Attempting to reconnect"
      close
      log(revive_connection)
      # hope this isn't an endless loop
      reconnect_if_necessary do 
        block.call
      end
    rescue
      log "Error: #{$!}"
      raise
    end

    def self.start(config)
      imap_client  = Vmail::ImapClient.new config
      imap_client.open
      imap_client
    end

    def self.daemon(config)
      $gmail = self.start(config)
      use_uri = config['drb_uri'] || nil # redundant but explicit
      DRb.start_service(use_uri, $gmail)
      uri = DRb.uri
      puts "Starting gmail service at #{uri}"
      uri
    end
  end
end

trap("INT") { 
  require 'timeout'
  puts "Closing imap connection"  
  begin
    Timeout::timeout(10) do 
      $gmail.close
    end
  rescue Timeout::Error
    puts "Close connection attempt timed out"
  end
  exit
}


