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
require 'vmail/reply_templating'

module Vmail
  class ImapClient
    include Vmail::Helpers
    include Vmail::AddressQuoter
    include Vmail::Searching
    include Vmail::ShowingHeaders
    include Vmail::ShowingMessage
    include Vmail::FlaggingAndMoving
    include Vmail::ReplyTemplating

    attr_accessor :max_seqno # of current mailbox

    def initialize(config)
      @username, @password = config['username'], config['password']
      @name = config['name']
      @signature = config['signature'] 
      @signature_script = config['signature_script'] 
      @always_cc = config['always_cc']
      @always_bcc = config['always_bcc']
      @mailbox = nil
      @logger = Logger.new(config['logfile'] || STDERR)
      @logger.level = Logger::DEBUG
      $logger = @logger
      @imap_server = config['server'] || 'imap.gmail.com'
      @imap_port = config['port'] || 993
      # generic smtp settings
      @smtp_server = config['smtp_server'] || 'smtp.gmail.com'
      @smtp_port = config['smtp_port'] || 587
      @smtp_domain = config['smtp_domain'] || 'gmail.com'
      @authentication = config['authentication'] || 'plain'
      @width = 100
      current_message = nil
    end


    def open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      log @imap.login(@username, @password)
      list_mailboxes # prefetch mailbox list
    rescue 
      puts "VMAIL_ERROR: #{[$!.message, $!.backtrace].join("\n")}"
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
      Timeout::timeout(5) do
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
      reconnect_if_necessary(30) do 
        log @imap.select(mailbox)
      end
      log "Done"

      @mailbox = mailbox
      @label = Label[name: @mailbox] || Label.create(name: @mailbox)

      log "Getting mailbox status"
      get_mailbox_status
      log "Getting highest message id"
      get_highest_message_id
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
      res = @imap.search(['ALL'])
      if res && res[-1]
        @num_messages = res[-1]
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

    def check_for_new_messages
      log "Checking for new messages"
      if search_query?
        log "Update aborted because query is search query: #{@query.inspect}"
        return ""
      end
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
      # reset the max_seqno
      self.max_seqno = ids.max
      log "- setting max_seqno to #{self.max_seqno}"
      log "- new uids found: #{new_ids.inspect}"
      new_ids
    end

    def update
      prime_connection
      new_ids = check_for_new_messages 
      if !new_ids.empty?
        @ids = @ids + new_ids
        message_ids = fetch_and_cache_headers(new_ids)
        res = get_message_headers(message_ids)
        res
      else
        ''
      end
    rescue
      puts "VMAIL_ERROR: #{[$!.message, $!.backtrace].join("\n")}"
    end

    # gets 100 messages prior to id
    def more_messages
      log "Getting more_messages"
      log "Old start_index: #{@start_index}"
      max = @start_index - 1
      @start_index = [(max + 1 - @limit), 1].max
      log "New start_index: #{@start_index}"
      fetch_ids = search_query? ? @ids[@start_index..max] : (@start_index..max).to_a
      log fetch_ids.inspect
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

    def append_to_file(message_ids, file)
      message_ids = message_ids.split(',')
      log "Append to file uid set #{message_ids.inspect} to file: #{file}"
      message_ids.each do |message_id|
        message = show_message(message_id)
        File.open(file, 'a') {|f| f.puts(divider('=') + "\n" + message + "\n\n")}
        subject = (message[/^subject:(.*)/,1] || '').strip
        log "Appended message '#{subject}'"
      end
      "Printed #{message_ids.size} message#{message_ids.size == 1 ? '' : 's'} to #{file.strip}"
    end

    def new_message_template(subject = nil, append_signature = true)
      headers = {'from' => "#{@name} <#{@username}>",
        'to' => nil,
        'subject' => subject,
        'cc' => @always_cc,
        'bcc' => @always_bcc
      }
      format_headers(headers) + (append_signature ? ("\n\n" + signature) : "\n\n")
    end

    def format_headers(hash)
      lines = []
      hash.each_pair do |key, value|
        if value.nil? && key != 'to' && key != 'subject'
          next
        end
        if value.is_a?(Array)
          value = value.join(", ")
        end
        lines << "#{key.gsub("_", '-')}: #{value}"
      end
      lines.join("\n")
    end


    def signature
      return signature_script if @signature_script
      "\n\n#@signature"
    end

    def signature_script
      return unless @signature_script
      %x{ #{@signature_script.strip} }
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
      prime_connection
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
        if key == 'references'
          mail.references = value
        else
          next if (value.nil? || value.strip == '')
          log [key, value].join(':')
          if %w(from to cc bcc).include?(key)
            value = quote_addresses(value)
          end
          headers[key] = value
        end
      end
      log "Delivering message with headers: #{headers.to_yaml}"
      mail.from = headers['from'] || @username
      mail.to = headers['to'] #.split(/,\s+/)
      mail.cc = headers['cc'] #&& headers['cc'].split(/,\s+/)
      mail.bcc = headers['bcc'] #&& headers['cc'].split(/,\s+/)
      mail.subject = headers['subject']
      mail.from ||= @username
      mail.charset = 'UTF-8'
      # attachments are added as a snippet of YAML after a blank line
      # after the headers, and followed by a blank line
      if (attachments_section = raw_body.split(/\n\s*\n/, 2)[0]) =~ /^attach(ment|ments)*:/
        files = attachments_section.split(/\n/).map {|line| line[/[-:]\s*(.*)\s*$/, 1]}.compact
        log "Attach: #{files.inspect}"
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
      mail.text_part.charset = 'UTF-8'
      mail
    rescue
      $logger.debug $!
      raise
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
      @width = width.to_i
      log "Setting window width to #{width}"
    end
   
    def smtp_settings
      [:smtp, {:address => @smtp_server,
      :port => @smtp_port,
      :domain => @smtp_domain,
      :user_name => @username,
      :password => @password,
      :authentication => @authentication,
      :enable_starttls_auto => true}]
    end

    def log(string)
      if string.is_a?(::Net::IMAP::TaggedResponse)
        string = string.raw_data
      end
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
      imap_client  = self.new config
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
    #Timeout::timeout(2) do 
      # just try to quit
      # $gmail.close
    #end
  rescue Timeout::Error
    puts "Close connection attempt timed out"
  end
  exit
}


