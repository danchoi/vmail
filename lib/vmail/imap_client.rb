require 'drb'
require 'vmail/message_formatter'
require 'vmail/string_ext'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'
require 'logger'

module Vmail
  class ImapClient

    MailboxAliases = { 'sent' => '[Gmail]/Sent Mail',
      'all' => '[Gmail]/All Mail',
      'starred' => '[Gmail]/Starred',
      'important' => '[Gmail]/Important',
      'drafts' => '[Gmail]/Drafts',
      'spam' => '[Gmail]/Spam',
      'trash' => '[Gmail]/Trash'
    }

    def initialize(config)
      @username, @password = config['username'], config['password']
      @name = config['name']
      @signature = config['signature']
      @mailbox = nil
      @logger = Logger.new(config['logfile'] || STDERR)
      @logger.level = Logger::DEBUG
      @current_mail = nil
      @current_uid = nil
      @imap_server = config['server'] || 'imap.gmail.com'
      @imap_port = config['port'] || 993
    end

    def open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
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
      max_uid = uid_set.max
      log "fetch headers for #{uid_set.inspect}"
      if uid_set.empty?
        log "empty set"
        return ""
      end
      results = reconnect_if_necessary do 
        @imap.uid_fetch(uid_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE" ])
      end
      log "extracting headers"
      lines = results.
        sort_by {|x| 
          begin
            Time.parse(x.attr['ENVELOPE'].date) 
          rescue ArgumentError
            Time.now
          end
        }.
        map {|x| format_header(x, max_uid)}
      log "returning result" 
      return lines.join("\n")
    end

    def format_header(fetch_data, max_uid=nil)
      uid = fetch_data.attr["UID"]
      envelope = fetch_data.attr["ENVELOPE"]
      size = fetch_data.attr["RFC822.SIZE"]
      flags = fetch_data.attr["FLAGS"]
      address_struct = if @mailbox == '[Gmail]/Sent Mail' 
                         structs = envelope.to || envelope.cc
                         structs.nil? ? nil : structs.first 
                       else
                         envelope.from.first
                       end
      address = if address_struct.nil?
                  "unknown"
                elsif address_struct.name
                  "#{Mail::Encodings.unquote_and_convert_to(address_struct.name, 'UTF-8')} <#{[address_struct.mailbox, address_struct.host].join('@')}>"
                else
                  [address_struct.mailbox, address_struct.host].join('@') 
                end
      if @mailbox == '[Gmail]/Sent Mail' && envelope.to && envelope.cc
        total_recips = (envelope.to + envelope.cc).size
        address += " + #{total_recips - 1}"
      end
      date = begin 
               Time.parse(envelope.date).localtime
             rescue ArgumentError
               Time.now
             end

      date_formatted = if date.year != Time.now.year
                         date.strftime "%b %d %Y" rescue envelope.date.to_s 
                       else 
                         date.strftime "%b %d %I:%M%P" rescue envelope.date.to_s 
                       end
      subject = envelope.subject || ''
      subject = Mail::Encodings.unquote_and_convert_to(subject, 'UTF-8')
      flags = format_flags(flags)
      first_col_width = max_uid.to_s.length 
      mid_width = @width - (first_col_width + 33)
      address_col_width = (mid_width * 0.3).ceil
      subject_col_width = (mid_width * 0.7).floor
      [uid.to_s.col(first_col_width), 
        (date_formatted || '').col(14),
        address.col(address_col_width),
        subject.col(subject_col_width),
        number_to_human_size(size).rcol(6),
        flags.rcol(7)].join(' ')
    end

    UNITS = [:b, :kb, :mb, :gb].freeze

    # borrowed from ActionView/Helpers
    def number_to_human_size(number)
      if number.to_i < 1024
        "#{number} b"
      else
        max_exp = UNITS.size - 1
        exponent = (Math.log(number) / Math.log(1024)).to_i # Convert to base 1024
        exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
        number  /= 1024 ** exponent
        unit = UNITS[exponent]
        "#{number} #{unit}"
      end
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
        log "priming connection for update"
        res = @imap.uid_fetch(@all_uids[-1], ["ENVELOPE"])
        if res.nil?
          raise IOError, "IMAP connection seems broken"
        end
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

    def show_message(uid, raw=false, forwarded=false)
      uid = uid.to_i
      if forwarded
        return @current_message.split(/\n-{20,}\n/, 2)[1]
      end
      return @current_mail.to_s if raw 
      return @current_message if uid == @current_uid 
      log "fetching #{uid.inspect}" 
      fetch_data = reconnect_if_necessary do 
        @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])[0]
      end
      res = fetch_data.attr["RFC822"]
      mail = Mail.new(res) 
      @current_uid = uid
      @current_mail = mail # used later to show raw message or extract attachments if any
      log "saving current mail with parts: #{@current_mail.parts.inspect}"
      formatter = Vmail::MessageFormatter.new(mail)
      out = formatter.process_body 
      size = fetch_data.attr["RFC822.SIZE"]
      @current_message = <<-EOF
#{@mailbox} #{uid} #{number_to_human_size size} #{format_parts_info(formatter.list_parts)}
---------------------------------------
#{format_headers(formatter.extract_headers)}

#{out}
EOF
    rescue
      log "parsing error"
      "Error encountered parsing this message:\n#{$!}"
    end

    def format_parts_info(parts)
      lines = parts.select {|part| part !~ %r{text/plain}}
      if lines.size > 0
        "\n#{lines.join("\n")}"
      end
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
          unless @mailbox == '[Gmail]/Trash'
            @imap.uid_copy(uid_set, "[Gmail]/Trash")
          end
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

    def move_to(uid_set, mailbox)
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      create_if_necessary mailbox
      log "move_to #{uid_set.inspect} #{mailbox}"
      if uid_set.is_a?(String)
        uid_set = uid_set.split(",").map(&:to_i)
      end
      log @imap.uid_copy(uid_set, mailbox)
      log @imap.uid_store(uid_set, '+FLAGS', [:Deleted])
    end

    def copy_to(uid_set, mailbox)
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      create_if_necessary mailbox
      log "copy #{uid_set.inspect} #{mailbox}"
      if uid_set.is_a?(String)
        uid_set = uid_set.split(",").map(&:to_i)
      end
      log @imap.uid_copy(uid_set, mailbox)
    end

    def create_if_necessary(mailbox)
      if !@mailboxes.include?(mailbox) 
        log "creating mailbox #{mailbox}"
        log @imap.create(mailbox) 
        @mailboxes = nil # force reload next fime list_mailboxes() called
      end
    end

    def append_to_file(file, uid_set)
      if uid_set.is_a?(String)
        uid_set = uid_set.split(",").map(&:to_i)
      end
      log "append messages to file: #{file}"
      uid_set.each do |uid|
        message = show_message(uid)
        divider = "#{'=' * 39}\n"
        File.open(file, 'a') {|f| f.puts(divider + message + "\n\n")}
        log "appended uid #{uid}"
      end
      "printed #{uid_set.size} message#{uid_set.size == 1 ? '' : 's'} to #{file.strip}"
    end


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
        lines << "#{key.gsub("_", '-')}: #{value}"
      end
      lines.join("\n")
    end

    def reply_template(uid, replyall=false)
      log "sending reply template for #{uid}"
      fetch_data = @imap.uid_fetch(uid.to_i, ["FLAGS", "ENVELOPE", "RFC822"])[0]
      envelope = fetch_data.attr['ENVELOPE']
      recipient = [envelope.reply_to, envelope.from].flatten.map {|x| address_to_string(x)}[0]
      cc = [envelope.to, envelope.cc]
      cc = cc.flatten.compact.
        select {|x| @username !~ /#{x.mailbox}@#{x.host}/}.
        map {|x| address_to_string(x)}.join(", ")
      mail = Mail.new fetch_data.attr['RFC822']
      formatter = Vmail::MessageFormatter.new(mail)
      headers = formatter.extract_headers
      subject = headers['subject']
      if subject !~ /Re: /
        subject = "Re: #{subject}"
      end
      cc = replyall ? cc : nil
      date = headers['date'].is_a?(String) ? Time.parse(headers['date']) : headers['date']
      quote_header = "On #{date.strftime('%a, %b %d, %Y at %I:%M %p')}, #{recipient} wrote:\n\n"
      body = quote_header + formatter.process_body.gsub(/^(?=>)/, ">").gsub(/^(?!>)/, "> ")
      reply_headers = { 'from' => "#@name <#@username>", 'to' => recipient, 'cc' => cc, 'subject' => headers['subject']}
      format_headers(reply_headers) + "\n\n\n" + body + signature
    end

    def address_to_string(x)
      x.name ? "#{x.name} <#{x.mailbox}@#{x.host}>" : "#{x.mailbox}@#{x.host}"
    end

    def signature
      return '' unless @signature
      "\n\n#@signature"
    end

    def forward_template(uid)
      original_body = show_message(uid, false, true)
      new_message_template + 
        "\n---------- Forwarded message ----------\n" +
        original_body + signature
    end

    def deliver(text)
      # parse the text. The headers are yaml. The rest is text body.
      require 'net/smtp'
      reconnect_if_necessary(4) do 
        # this is just to prime the IMAP connection
        # It's necessary for some reason.
        log "priming connection for delivering"
        res = @imap.uid_fetch(@all_uids[-1], ["ENVELOPE"])
        if res.nil?
          raise IOError, "IMAP connection seems broken"
        end
      end 
      mail = new_mail_from_input(text)
      mail.delivery_method(*smtp_settings)
      log mail.deliver!
      "message '#{mail.subject}' sent"
    end

    def save_draft(text)
      mail = new_mail_from_input(text)
      log "saving draft"
      reconnect_if_necessary do 
        log "saving draft"
        log @imap.append("[Gmail]/Drafts", text.gsub(/\n/, "\r\n"), [:Seen], Time.now)
      end
    end

    # TODO
    def resume_draft
      # chop off top three lines (this is hackey, fix later)
      # text = text.split("\n")[3..-1].join("\n")
      # delete date: field
      # text = text.sub("^date:\s*$", "")
    end

    def new_mail_from_input(text)
      require 'mail'
      mail = Mail.new
      raw_headers, raw_body = *text.split(/\n\s*\n/, 2)
      headers = {}
      raw_headers.split("\n").each do |line|
        key, value = *line.split(/:\s*/, 2)
        headers[key] = value
      end
      log "headers: #{headers.inspect}"
      log "delivering: #{headers.inspect}"
      mail.from = headers['from'] || @username
      mail.to = headers['to'] #.split(/,\s+/)
      mail.cc = headers['cc'] #&& headers['cc'].split(/,\s+/)
      mail.bcc = headers['bcc'] #&& headers['cc'].split(/,\s+/)
      mail.subject = headers['subject']
      mail.from ||= @username
      # attachments are added as a snippet of YAML after a blank line
      # after the headers, and followed by a blank line
      if (attachments = raw_body.split(/\n\s*\n/, 2)[0]) =~ /^attach(ment|ments)*:/
        # TODO
        files = YAML::load(attachments).values.flatten
        log "attach: #{files}"
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
      log "save_attachments #{dir}"
      if !@current_mail
        log "missing a current message"
      end
      return unless dir && @current_mail
      attachments = @current_mail.attachments
      `mkdir -p #{dir}`
      saved = attachments.map do |x|
        path = File.join(dir, x.filename)
        log "saving #{path}"
        File.open(path, 'wb') {|f| f.puts x.decoded}
        path
      end
      "saved:\n" + saved.map {|x| "- #{x}"}.join("\n")
    end

    def open_html_part(uid)
      log "open_html_part #{uid}"
      log @current_mail.parts.inspect
      multipart = @current_mail.parts.detect {|part| part.multipart?}
      html_part = if multipart 
                    multipart.parts.detect {|part| part.header["Content-Type"].to_s =~ /text\/html/}
                  elsif ! @current_mail.parts.empty?
                    @current_mail.parts.detect {|part| part.header["Content-Type"].to_s =~ /text\/html/}
                  else
                    @current_mail.body
                  end
      return if html_part.nil?
      outfile = 'vmail-htmlpart.html'
      File.open(outfile, 'w') {|f| f.puts(html_part.decoded)}
      # client should handle opening the html file
      return outfile
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
      # if this times out, we know the connection is stale while the user is
      # trying to update
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

    def self.start(config)
      imap_client  = Vmail::ImapClient.new config
      imap_client.open
      imap_client
    end

    def self.daemon(config)
      $gmail = self.start(config)
      DRb.start_service(nil, $gmail)
      uri = DRb.uri
      puts "starting gmail service at #{uri}"
      uri
    end
  end
end

trap("INT") { 
  require 'timeout'
  puts "closing imap connection"  
  begin
    Timeout::timeout(5) do 
      $gmail.close
    end
  rescue Timeout::Error
    puts "close connection attempt timed out"
  end
  exit
}


