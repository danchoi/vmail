# encoding: UTF-8
require 'drb'
require 'vmail/string_ext'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'
require 'logger'

module Vmail
  class ImapClient
    DIVIDER_WIDTH = 46

    MailboxAliases = { 'sent' => '[Gmail]/Sent Mail',
      'all' => '[Gmail]/All Mail',
      'starred' => '[Gmail]/Starred',
      'important' => '[Gmail]/Important',
      'drafts' => '[Gmail]/Drafts',
      'spam' => '[Gmail]/Spam',
      'trash' => '[Gmail]/Trash'
    }

    attr_accessor :max_seqno # of current mailbox

    def initialize(config)
      @username, @password = config['username'], config['password']
      @name = config['name']
      @signature = config['signature']
      @mailbox = nil
      @logger = Logger.new(config['logfile'] || STDERR)
      @logger.level = Logger::DEBUG
      @imap_server = config['server'] || 'imap.gmail.com'
      @imap_port = config['port'] || 993
      @current_mail = nil
      @current_message_uid = nil
      @width = 140
    end

    # holds mail objects keyed by [mailbox, uid]
    def message_cache
      @message_cache ||= {}
      size = @message_cache.values.reduce(0) {|sum, x| sum + x[:size]}
      if size > 2_000_000 # TODO make this configurable
        log "PRUNING MESSAGE CACHE; message cache is consuming #{number_to_human_size size}"
        @message_cache.keys[0, @message_cache.size / 2].each {|k| @message_cache.delete(k)}
      end
      @message_cache
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
      log "closing connection"
      Timeout::timeout(10) do
        @imap.close rescue Net::IMAP::BadResponseError
        @imap.disconnect rescue IOError
      end
    rescue Timeout::Error
    end

    def select_mailbox(mailbox, force=false)
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      if mailbox == @mailbox && !force
        return
      end
      log "selecting mailbox #{mailbox.inspect}"
      reconnect_if_necessary(15) do 
        log @imap.select(mailbox)
      end
      log "done"
      @mailbox = mailbox
      log "getting mailbox status"
      get_mailbox_status
      log "getting highest message id"
      get_highest_message_id
      return "OK"
    end

    def reload_mailbox
      return unless STDIN.tty?
      select_mailbox(@mailbox, true)
    end

    def clear_cached_message
      return unless STDIN.tty?
      log "CLEARING CACHED MESSAGE"
      @current_mail = nil
      @current_message_uid = nil
      @current_message = nil
    end

    def get_highest_message_id
      # get highest message ID
      res = @imap.fetch([1,"*"], ["ENVELOPE"])
      if res 
        @num_messages = res[-1].seqno
        log "HIGHEST ID: #@num_messages"
      else
        @num_messages = 1
        log "NO HIGHEST ID: setting @num_messages to 1"
      end
    end

    # not used for anything
    def get_mailbox_status
      return
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
      return if @ids.nil? || @ids.empty?
      reconnect_if_necessary(4) do 
        # this is just to prime the IMAP connection
        # It's necessary for some reason before update and deliver. 
        log "priming connection"
        res = @imap.fetch(@ids[-1], ["ENVELOPE"])
        if res.nil?
          # just go ahead, just log
          log "priming connection didn't work, connection seems broken, but still going ahead..."
        end
      end 
    end

    def list_mailboxes
      log 'loading mailboxes...'
      @mailboxes ||= ((@imap.list("[Gmail]/", "%") || []) + (@imap.list("", "*")) || []).
        select {|struct| struct.attr.none? {|a| a == :Noselect} }.
        map {|struct| struct.name}.
        map {|name| MailboxAliases.invert[name] || name}
      @mailboxes.delete("INBOX")
      @mailboxes.unshift("INBOX")
      log "loaded mailboxes: #{@mailboxes.inspect}"
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
    def fetch_row_text(id_set, are_uids=false, is_update=false)
      log "fetch_row_text: #{id_set.inspect}"
      if id_set.is_a?(String)
        id_set = id_set.split(',')
      end
      if id_set.to_a.empty?
        log "- empty set"
        return ""
      end
      new_message_rows = fetch_envelopes(id_set, are_uids, is_update)
      new_message_rows.map {|x| x[:row_text]}.join("\n")
    rescue # Encoding::CompatibilityError (only in 1.9.2)
      log "Error in fetch_row_text:\n#{$!}\n#{$!.backtrace}"
      new_message_rows.map {|x| Iconv.conv('US-ASCII//TRANSLIT//IGNORE', 'UTF-8', x[:row_text])}.join("\n")
    end

    def fetch_envelopes(id_set, are_uids, is_update)
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
      log "- extracting headers"
      new_message_rows = results.map {|x| extract_row_data(x) }
      log "- returning #{new_message_rows.size} new rows and caching result"  
      new_message_rows
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
      identifier = [seqno.to_i, uid.to_i].join(':')
      row_text = [ flags.col(2),
                   (date_formatted || '').col(14),
                   address.col(address_col_width),
                   subject.col(subject_col_width), 
                   number_to_human_size(size).rcol(7), 
                   identifier.to_s
      ].join(' | ')
      {:uid => uid, :seqno => seqno, :row_text => row_text}
    rescue 
      log "error extracting header for uid #{uid} seqno #{seqno}: #$!\n#{$!.backtrace}"
      row_text = "#{seqno.to_s} : error extracting this header"
      {:uid => uid, :seqno => seqno, :row_text => row_text}
    end

    UNITS = [:b, :kb, :mb, :gb].freeze

    # borrowed from ActionView/Helpers
    def number_to_human_size(number)
      if number.to_i < 1024
        "<1kb" # round up to 1kh
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
      # other flags like "Old" should be hidden here
      flags = flags.map {|flag| FLAGMAP[flag] || flag}
      flags.delete("Old")
      if flags.delete(:Seen).nil?
        flags << '+' # unread
      end
      flags.join('')
    end

    def search(query)
      query = Vmail::Query.parse(query)
      @limit = query.shift.to_i
      # a limit of zero is effectively no limit
      if @limit == 0
        @limit = @num_messages
      end
      if query.size == 1 && query[0].downcase == 'all'
        # form a sequence range
        query.unshift [[@num_messages - @limit + 1 , 1].max, @num_messages].join(':')
        @all_search = true
      else # this is a special query search
        # set the target range to the whole set
        query.unshift "1:#@num_messages"
        @all_search = false
      end
      @query = query.map {|x| x.to_s.downcase}
      query_string = Vmail::Query.args2string(@query)
      log "search query: #{@query} > #{query_string.inspect}"
      log "- @all_search #{@all_search}"
      @query = query
      @ids = reconnect_if_necessary(180) do # increase timeout to 3 minutes
        @imap.search(query_string)
      end
      # save ids in @ids, because filtered search relies on it
      fetch_ids = if @all_search
                    @ids
                  else #filtered search
                    @start_index = [@ids.length - @limit, 0].max
                    @ids[@start_index..-1]
                  end
      self.max_seqno = @ids[-1]
      log "- search query got #{@ids.size} results; max seqno: #{self.max_seqno}" 
      clear_cached_message
      res = fetch_row_text(fetch_ids)
      if STDOUT.tty?
        add_more_message_line(res, fetch_ids[0])
      else
        # non interactive mode
        puts [@mailbox, res].join("\n")
      end
    rescue
      log "ERROR:\n#{$!.inspect}\n#{$!.backtrace.join("\n")}"
    end

    def decrement_max_seqno(num)
      return unless STDIN.tty?
      log "Decremented max seqno from #{self.max_seqno} to #{self.max_seqno - num}"
      self.max_seqno -= num
    end

    def update
      prime_connection
      old_num_messages = @num_messages
      # we need to re-select the mailbox to get the new highest id
      reload_mailbox
      update_query = @query.dup
      # set a new range filter
      # this may generate a negative rane, e.g., "19893:19992" but that seems harmless
      update_query[0] = "#{old_num_messages}:#{@num_messages}"
      ids = reconnect_if_necessary { 
        log "search #update_query"
        @imap.search(Vmail::Query.args2string(update_query))
      }
      log "- got seqnos: #{ids.inspect}"
      log "- getting seqnos > #{self.max_seqno}"
      new_ids = ids.select {|seqno| seqno > self.max_seqno}
      @ids = @ids + new_ids
      log "- update: new uids: #{new_ids.inspect}"
      if !new_ids.empty?
        self.max_seqno = new_ids[-1]
        res = fetch_row_text(new_ids, false, true)
        res
      else
        nil
      end
    end

    # gets 100 messages prior to id
    def more_messages(message_id, limit=100)
      log "more_messages: message_id #{message_id}"
      message_id = message_id.to_i
      if @all_search 
        x = [(message_id - limit), 0].max
        y = [message_id - 1, 0].max

        res = fetch_row_text((x..y))
        add_more_message_line(res, x)
      else # filter search query
        log "@start_index #@start_index"
        x = [(@start_index - limit), 0].max
        y = [@start_index - 1, 0].max
        @start_index = x
        res = fetch_row_text(@ids[x..y]) 
        add_more_message_line(res, @ids[x])
      end
    end

    def add_more_message_line(res, start_seqno)
      log "add_more_message_line for start_seqno #{start_seqno}"
      if @all_search
        return res if start_seqno.nil?
        remaining = start_seqno - 1
      else # filter search
        remaining = (@ids.index(start_seqno) || 1) - 1
      end
      if remaining < 1
        log "none remaining"
        return "showing all matches\n" + res
      end
      log "remaining messages: #{remaining}"
      ">  Load #{[100, remaining].min} more messages. #{remaining} remaining.\n" + res
    end

    def show_message(uid, raw=false)
      log "show message: #{uid}"
      return @current_mail.to_s if raw 
      uid = uid.to_i
      if uid == @current_message_uid 
        return @current_message 
      end

      #prefetch_adjacent(index) # deprecated

      # TODO keep state in vim buffers, instead of on Vmail Ruby client
      # envelope_data[:row_text] = envelope_data[:row_text].gsub(/^\+ /, '  ').gsub(/^\*\+/, '* ') # mark as read in cache
      #seqno = envelope_data[:seqno]

      log "showing message uid: #{uid}"
      data = if x = message_cache[[@mailbox, uid]]
               log "- message cache hit"
               x
             else 
               log "- fetching and storing to message_cache[[#{@mailbox}, #{uid}]]"
               fetch_and_cache(uid)
             end
      if data.nil?
        # retry, though this is a hack!
        log "- data is nil. retrying..."
        return show_message(uid, raw)
      end
      # make this more DRY later by directly using a ref to the hash
      mail = data[:mail]
      size = data[:size] 
      @current_message_uid = uid
      log "- setting @current_mail"
      @current_mail = mail # used later to show raw message or extract attachments if any
      @current_message = data[:message_text]
    rescue
      log "parsing error"
      "Error encountered parsing this message:\n#{$!}\n#{$!.backtrace.join("\n")}"
    end

    def fetch_and_cache(uid)
      if data = message_cache[[@mailbox, uid]] 
        return data
      end
      fetch_data = reconnect_if_necessary do 
        res = @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        if res.nil?
          # retry one more time ( find a more elegant way to do this )
          res = @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        end
        res[0] 
      end
      # USE THIS
      size = fetch_data.attr["RFC822.SIZE"]
      flags = fetch_data.attr["FLAGS"]
      mail = Mail.new(fetch_data.attr['RFC822'])
      formatter = Vmail::MessageFormatter.new(mail)
      message_text = <<-EOF
#{@mailbox} uid:#{uid} #{number_to_human_size size} #{flags.inspect} #{format_parts_info(formatter.list_parts)}
#{divider '-'}
#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
      # log "storing message_cache[[#{@mailbox}, #{uid}]]"
      d = {:mail => mail, :size => size, :message_text => message_text, :seqno => fetch_data.seqno, :flags => flags}
      message_cache[[@mailbox, uid]] = d
    rescue
      msg = "Error encountered parsing message uid  #{uid}:\n#{$!}\n#{$!.backtrace.join("\n")}" + 
        "\n\nRaw message:\n\n" + mail.to_s
      log msg
      log message_text
      {:message_text => msg}
    end

    # deprecated
    def prefetch_adjacent(index)
      Thread.new do 
        [index + 1, index - 1].each do |idx|
          fetch_and_cache(idx)
        end
      end
    end

    def format_parts_info(parts)
      lines = parts.select {|part| part !~ %r{text/plain}}
      if lines.size > 0
        "\n#{lines.join("\n")}"
      end
    end

    # id_set is a string comming from the vim client
    # action is -FLAGS or +FLAGS
    def flag(uid_set, action, flg)
      log "flag #{uid_set} #{flg} #{action}"
      uid_set = uid_set.split(',').map(&:to_i)
      if flg == 'Deleted'
        log "Deleting uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        # for delete, do in a separate thread because deletions are slow
        spawn_thread_if_tty do 
          unless @mailbox == '[Gmail]/Trash'
            log "@imap.uid_copy #{uid_set.inspect} to trash"
            log @imap.uid_copy(uid_set, "[Gmail]/Trash")
          end
          log "@imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
          reload_mailbox
          clear_cached_message
        end
      elsif flg == 'spam' || flg == '[Gmail]/Spam'
        log "Marking as spam uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        spawn_thread_if_tty do 
          log "@imap.uid_copy #{uid_set.inspect} to spam"
          log @imap.uid_copy(uid_set, "[Gmail]/Spam")
          log "@imap.uid_store #{uid_set.inspect} #{action} [:Deleted]"
          log @imap.uid_store(uid_set, action, [:Deleted])
          reload_mailbox
          clear_cached_message
        end
      else
        log "Flagging uid_set: #{uid_set.inspect}"
        spawn_thread_if_tty do
          log "@imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
        end
      end
    end

    def move_to(uid_set, mailbox)
      uid_set = uid_set.split(',').map(&:to_i)
      decrement_max_seqno(uid_set.size)
      log "move #{uid_set.inspect} to #{mailbox}"
      if mailbox == 'all'
        log "archiving messages"
      end
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      create_if_necessary mailbox
      log "moving uid_set: #{uid_set.inspect} to #{mailbox}"
      spawn_thread_if_tty do 
        log @imap.uid_copy(uid_set, mailbox)
        log @imap.uid_store(uid_set, '+FLAGS', [:Deleted])
        reload_mailbox
        clear_cached_message
        log "moved uid_set #{uid_set.inspect} to #{mailbox}"
      end
    end

    def copy_to(uid_set, mailbox)
      uid_set = uid_set.split(',').map(&:to_i)
      if MailboxAliases[mailbox]
        mailbox = MailboxAliases[mailbox]
      end
      create_if_necessary mailbox
      log "copying #{uid_set.inspect} to #{mailbox}"
      spawn_thread_if_tty do 
        log @imap.uid_copy(uid_set, mailbox)
        log "copied uid_set #{uid_set.inspect} to #{mailbox}"
      end
    end

    def spawn_thread_if_tty 
      if STDIN.tty?
        Thread.new do 
          yield
        end
      else
        yield
      end
    end

    def create_if_necessary(mailbox)
      current_mailboxes = mailboxes.map {|m| MailboxAliases[m] || m}
      if !current_mailboxes.include?(mailbox)
        log "current mailboxes: #{current_mailboxes.inspect}"
        log "creating mailbox #{mailbox}"
        log @imap.create(mailbox) 
        @mailboxes = nil # force reload ...
        list_mailboxes
      end
    end

    def append_to_file(uid_set, file)
      uid_set = uid_set.split(',').map(&:to_i)
      log "append to file uid set #{uid_set.inspect} to file: #{file}"
      uid_set.each do |uid|
        message = show_message(uid)
        File.open(file, 'a') {|f| f.puts(divider('=') + "\n" + message + "\n\n")}
        subject = (message[/^subject:(.*)/,1] || '').strip
        log "appended message '#{subject}'"
      end
      "printed #{uid_set.size} message#{uid_set.size == 1 ? '' : 's'} to #{file.strip}"
    end

    def new_message_template(subject = nil, append_signature = true)
      headers = {'from' => "#{@name} <#{@username}>",
        'to' => nil,
        'subject' => subject
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
      log "sending reply template"
      if @current_mail.nil?
        log "- missing @current mail!"
        return nil
      end
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
      formatter = Vmail::MessageFormatter.new(@current_mail)
      headers = formatter.extract_headers
      subject = headers['subject']
      if subject !~ /Fwd: /
        subject = "Fwd: #{subject}"
      end

      new_message_template(subject, false) + 
        "\n---------- Forwarded message ----------\n" +
        original_body + signature
    end

    def divider(str)
      str * DIVIDER_WIDTH
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
        "message '#{mail.subject}' sent"
      else
        "failed to deliver message '#{mail.subject}'"
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
        headers[key] = value
      end
      log "delivering message with headers: #{headers.to_yaml}"
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
      outfile = 'part.html'
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
    rescue IOError, Errno::EADDRNOTAVAIL, Errno::ECONNRESET, Timeout::Error
      log "error: #{$!}"
      log "attempting to reconnect"
      close
      log(revive_connection)
      # hope this isn't an endless loop
      reconnect_if_necessary do 
        block.call
      end
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
      use_uri = config['drb_uri'] || nil # redundant but explicit
      DRb.start_service(use_uri, $gmail)
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
    Timeout::timeout(10) do 
      $gmail.close
    end
  rescue Timeout::Error
    puts "close connection attempt timed out"
  end
  exit
}


