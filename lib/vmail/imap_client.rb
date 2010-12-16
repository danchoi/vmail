require 'drb'
require 'vmail/message_formatter'
require 'vmail/reply_template'
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
      @current_message_index = nil
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

    def select_mailbox(mailbox, force=false)
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      if mailbox == @mailbox && !force
        return
      end
      log "selecting mailbox #{mailbox.inspect}"
      reconnect_if_necessary do 
        log @imap.select(mailbox)
      end
      @mailbox = mailbox
      get_mailbox_status
      get_highest_message_id
      return "OK"
    end

    def reload_mailbox
      select_mailbox(@mailbox, true)
    end

    def get_highest_message_id
      # get highest message ID
      res = @imap.fetch([1,"*"], ["ENVELOPE"])
      @num_messages = res[-1].seqno
      log "HIGHEST ID: #@num_messages"
    end

    def get_mailbox_status
      @status = @imap.status(@mailbox,  ["MESSAGES", "RECENT", "UNSEEN"])
      log "mailbox status: #{@status.inspect}"
    end

    def revive_connection
      log "reviving connection"
      open
      log "reselecting mailbox #@mailbox"
      @imap.select(@mailbox)
    end

    def prime_connection
      reconnect_if_necessary(4) do 
        # this is just to prime the IMAP connection
        # It's necessary for some reason before update and deliver. 
        log "priming connection for delivering"
        res = @imap.fetch(@ids[-1], ["ENVELOPE"])
        if res.nil?
          raise IOError, "IMAP connection seems broken"
        end
      end 
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

    # called internally, not by vim client
    def mailboxes
      if @mailboxes.nil?
        list_mailboxes
      end
      @mailboxes
    end

    # id_set may be a range, array, or string
    def fetch_envelopes(id_set, are_uids=false)
      log "fetch_envelopes: #{id_set.inspect}"
      if id_set.is_a?(String)
        id_set = id_set.split(',')
      end
      if id_set.to_a.empty?
        log "empty set"
        return ""
      end
      results = reconnect_if_necessary do 
        if are_uids
          @imap.uid_fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID" ])
        else
          @imap.fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID" ])
        end
      end
      if results.nil?
        error = "expected fetch results but got nil"
        log(error) && raise(error)
      end
      log "extracting headers"
      new_message_rows = results.map {|x| extract_row_data(x) }
      if are_uids
        # replace old row_text values
        new_message_rows.each {|new_row_data|
          @message_list.
            select {|old_row_data| old_row_data[:uid] == new_row_data[:uid]}.
            each {|old_row_data| old_row_data[:row_text] = new_row_data[:row_text]}
        }
      else
        # put new rows before the current ones
        @message_list.unshift(*new_message_rows)
      end
      log "returning #{new_message_rows.size} new rows" 
      return new_message_rows.
        map {|x| x[:row_text]}.
        join("\n")
    end

    # TODO extract this to another class or module and write unit tests
    def extract_row_data(fetch_data)
      seqno = fetch_data.seqno
      uid = fetch_data.attr['UID']
      # log "fetched seqno #{seqno} uid #{uid}"
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
                  [Mail::Encodings.unquote_and_convert_to(address_struct.mailbox, 'UTF-8'), Mail::Encodings.unquote_and_convert_to(address_struct.host, 'UTF-8')].join('@') 
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
      mid_width = @width - 38
      address_col_width = (mid_width * 0.3).ceil
      subject_col_width = (mid_width * 0.7).floor
      row_text = [ flags.col(2),
                   (date_formatted || '').col(14),
                   address.col(address_col_width),
                   subject.col(subject_col_width), 
                   number_to_human_size(size).rcol(6) ].join('|')
      {:uid => uid, :seqno => seqno, :row_text => row_text}
    rescue 
      log "error extracting header for uid #{uid} seqno #{seqno}: #$!"
      row_text = "#{seqno.to_s} : error extracting this header"
      {:uid => uid, :seqno => seqno, :row_text => row_text}
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
        "#{number}#{unit}"
      end
    end

    FLAGMAP = {:Flagged => '*'}
    # flags is an array like [:Flagged, :Seen]
    def format_flags(flags)
      flags = flags.map {|flag| FLAGMAP[flag] || flag}
      if flags.delete(:Seen).nil?
        flags << '+' # unread
      end
      flags.join('')
    end

    def search(limit, *query)
      limit = limit.to_i
      limit = 100 if limit.to_s !~ /^\d+$/
      query = ['ALL'] if query.empty?
      if query.size == 1 && query[0].downcase == 'all'
        # form a sequence range
        query.unshift [[@num_messages - limit.to_i + 1 , 1].max, @num_messages].join(':')
        @all_search = true
      else
        # this is a special query search
        # set the target range to the whole set
        query.unshift "1:#@num_messages"
        @all_search = false
      end
      log "@all_search #{@all_search}"
      @query = query
      log "search query: #@query.inspect"
      @ids = reconnect_if_necessary do
        @imap.search(@query.join(' '))
      end
      # save ids in @ids, because filtered search relies on it
      fetch_ids = if @all_search
                    @ids
                  else #filtered search
                    @start_index = [@ids.length - limit, 0].max
                    @ids[@start_index..-1]
                  end
      log "search query got #{@ids.size} results" 
      @message_list = [] # this will hold all the data extracted from these message envelopes
      res = fetch_envelopes(fetch_ids)
      add_more_message_line(res, fetch_ids[0])
    end

    def update
      prime_connection
      old_num_messages = @num_messages
      # we need to re-select the mailbox to get the new highest id
      reload_mailbox
      update_query = @query
      # set a new range filter
      update_query[0] = "#{old_num_messages}:#{@num_messages}"
      ids = reconnect_if_necessary { 
        log "search #update_query"
        @imap.search(update_query.join(' ')) 
      }
      # TODO change this. will throw error now
      new_ids = ids.select {|x| x > @ids.max}
      @ids = @ids + new_ids
      log "UPDATE: NEW UIDS: #{new_ids.inspect}"
      if !new_ids.empty?
        res = fetch_envelopes(new_ids)
        res
      end
    end

    # gets 100 messages prior to id
    def more_messages(limit=100)
      message_id = @message_list[0][:seqno]
      log "more_messages: message_id #{message_id}"
      message_id = message_id.to_i
      if @all_search 
        x = [(message_id - limit), 0].max
        y = [message_id - 1, 0].max
        res = fetch_envelopes((x..y))
        add_more_message_line(res, x)
      else
        # filter search query
        log "@start_index #@start_index"
        x = [(@start_index - limit), 0].max
        y = [@start_index - 1, 0].max
        @start_index = x
        res = fetch_envelopes(@ids[x..y]) 
        add_more_message_line(res, @ids[x])
      end
    end

    def add_more_message_line(res, start_id)
      log "add_more_message_line for start_id #{start_id}"
      if @all_search
        return res if start_id.nil?
        if start_id <= 1
          return res
        end
        remaining = start_id - 1
      else # filter search
        remaining = @ids.index(start_id) - 1
      end
      if remaining < 1
        log "none remaining"
        return res
      end
      log "remaining messages: #{remaining}"
      ">  Load #{[100, remaining].min} more messages. #{remaining} remaining.\n" + res
    end

    def show_message(index, raw=false)
      log "showing message at #{index}" 
      return @current_mail.to_s if raw 
      index = index.to_i
      return @current_message if index == @current_message_index 
      envelope_data = @message_list[index]
      uid = envelope_data[:uid] 
      log "fetching uid #{uid}"
      fetch_data = reconnect_if_necessary do 
        @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])[0]
      end
      res = fetch_data.attr["RFC822"]
      mail = Mail.new(res) 
      @current_message_index = index
      @current_mail = mail # used later to show raw message or extract attachments if any
      log "saving current mail with parts: #{@current_mail.parts.inspect}"
      formatter = Vmail::MessageFormatter.new(mail)
      out = formatter.process_body 
      size = fetch_data.attr["RFC822.SIZE"]
      @current_message = <<-EOF
#{@mailbox} seqno:#{index} uid:#{uid} #{number_to_human_size size} #{format_parts_info(formatter.list_parts)}
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

    # id_set is a string comming from the vim client
    # action is -FLAGS or +FLAGS
    def flag(index_range, action, flg)
      uid_set = uids_from_index_range(index_range)
      log "flag #{uid_set.inspect} #{flg} #{action}"
      if flg == 'Deleted'
        log "Deleting index_range: #{index_range.inspect}; uid_set: #{uid_set.inspect}"
        # for delete, do in a separate thread because deletions are slow
        Thread.new do 
          unless @mailbox == '[Gmail]/Trash'
            @imap.uid_copy(uid_set, "[Gmail]/Trash")
          end
          res = @imap.uid_store(uid_set, action, [flg.to_sym])
          remove_uid_set_from_cached_lists(uid_set)
          reload_mailbox
        end
      elsif flg == '[Gmail]/Spam'
        log "Marking as spam index_range: #{index_range.inspect}; uid_set: #{uid_set.inspect}"
        Thread.new do 
          @imap.uid_copy(uid_set, "[Gmail]/Spam")
          res = @imap.uid_store(uid_set, action, [:Deleted])
          remove_uid_set_from_cached_lists(uid_set)
          reload_mailbox
        end
        "#{id} deleted"
      else
        log "Flagging index_range: #{index_range.inspect}; uid_set: #{uid_set.inspect}"
        Thread.new do
          res = @imap.uid_store(uid_set, action, [flg.to_sym])
          log res.inspect
        end
      end
    end

    def uids_from_index_range(index_range_as_string)
      raise "expecting String" unless index_range_as_string.is_a?(String)
      raise "expecting a range as string" unless index_range_as_string =~ /^\d+\.\.\d+$/ 
      log "converting index_range #{index_range_as_string} to uids"
      uids = @message_list[eval(index_range_as_string)].map {|row| row[:uid]}
      log "converted index_range #{index_range_as_string} to uids #{uids.inspect}"
      uids
    end

    def remove_uid_set_from_cached_lists(uid_set)
      # delete from cached @ids and @message_list
      uid_set.each {|uid| 
        @message_list.
          select {|row| row[:uid] == uid}.
          each {|row| 
            seqno = row[:seqno]
            log "deleting seqno #{seqno} from @ids"
            @ids.delete seqno
            log "deleting msg uid #{row[:uid]} from @message_list"
            @message_list.delete(row)
          }
      }

    end

    def move_to(id_set, mailbox)
      log "move #{id_set.inspect} to #{mailbox}"
      if mailbox == 'all'
        log "archiving messages"
      end
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      create_if_necessary mailbox
      log "getting uids form index range #{id_set}"
      uid_set = uids_from_index_range(id_set)
      log "moving uid_set: #{uid_set.inspect} to #{mailbox}"
      Thread.new do 
        log @imap.uid_copy(uid_set, mailbox)
        log @imap.uid_store(uid_set, '+FLAGS', [:Deleted])
        reload_mailbox
        log "moved uid_set #{uid_set.inspect} to #{mailbox}"
      end
    end

    def copy_to(id_set, mailbox)
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      create_if_necessary mailbox
      uid_set = uids_from_index_range(id_set)
      log "copying #{uid_set.inspect} to #{mailbox}"
      Thread.new do 
        log @imap.uid_copy(uid_set, mailbox)
        log "copied uid_set #{uid_set.inspect} to #{mailbox}"
      end
    end

    def create_if_necessary(mailbox)
      current_mailboxes = mailboxes.map {|m| MailboxAliases[m] || m}
      if !current_mailboxes.include?(mailbox)
        log "current mailboxes: #{current_mailboxes.inspect}"
        log "creating mailbox #{mailbox}"
        log @imap.create(mailbox) 
        mailboxes = nil # force reload next fime list_mailboxes() called
      end
    end

    def append_to_file(file, index_range_as_string)
      raise "expecting a range as string" unless index_range_as_string =~ /^\d+\.\.\d+$/ 
      index_range = eval(index_range_as_string)
      log "append to file range #{index_range.inspect} to file: #{file}"
      index_range.each do |idx|
        message = show_message(idx)
        divider = "#{'=' * 39}\n"
        File.open(file, 'a') {|f| f.puts(divider + message + "\n\n")}
        subject = (message[/^subject:(.*)/,1] || '').strip
        log "appended message '#{subject}'"
      end
      "printed #{index_range.to_a.size} message#{index_range.to_a.size == 1 ? '' : 's'} to #{file.strip}"
    end


    def new_message_template
      headers = {'from' => "#{@name} <#{@username}>",
        'to' => nil,
        'subject' => nil
      }
      format_headers(headers) + "\n\n" + signature
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
      log "sending reply template"
      # user reply_template class
      reply_headers = Vmail::ReplyTemplate.new(@current_mail, @username, @name, replyall).reply_headers
      body = reply_headers.delete(:body)
      format_headers(reply_headers) + "\n\n\n" + body + signature
    end


    def signature
      return '' unless @signature
      "\n\n#@signature"
    end

    def forward_template
      original_body = @current_message.split(/\n-{20,}\n/, 2)[1]
      new_message_template + 
        "\n---------- Forwarded message ----------\n" +
        original_body + signature
    end

    def deliver(text)
      # parse the text. The headers are yaml. The rest is text body.
      require 'net/smtp'
      prime_connection
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

    def open_html_part
      log "open_html_part"
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
    rescue
      log "error: #{$!}"
      raise
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


