module Vmail
  module ShowingMessage

    def current_message
      return unless @cur_message_id
      Message[@cur_message_id]
    end

    def current_mail
      (c = current_message) && Mail.new(c.rfc822)
    end

    def cached_full_message?(message_id)
      m = Message[message_id]
      m && !m.plaintext.nil? && m
    end

    def show_message(message_id, raw=false)
      log "Show message: #{message_id}"
      return current_message.rfc822 if raw 
      log "Showing message message_id: #{message_id}"
      res = fetch_and_cache(message_id)
      if res.nil?
        # retry, though this is a hack!
        log "- data is nil. retrying..."
        return show_message(message_id, raw)
      end
      res
    end

    def fetch_and_cache(message_id)
      if message = cached_full_message?(message_id)
        log "- full message cache hit"        
        return message.plaintext
      end
      log "- full message cache miss"        
      labeling = Labeling[message_id: message_id, label_id: @label.id]
      uid = labeling.uid

      fetch_data = reconnect_if_necessary do 
        res = retry_once do
          @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        end
        res[0] 
      end
      seqno = fetch_data.seqno
      rfc822 = Mail.new(fetch_data.attr['RFC822'])
      formatter = Vmail::MessageFormatter.new rfc822

      message = Message[message_id]
      message_text = <<-EOF
#{message_id} #{number_to_human_size message.size} #{message.flags} #{format_parts_info(formatter.list_parts)}
#{divider '-'}
#{format_headers(formatter.extract_headers)}

#{formatter.plaintext_part}
EOF
      # 2 calls so we can see more fine grained exceptions
      message.update(:rfc822 => rfc822)
      if !message_text.valid_encoding?
        ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
        message_text = ic.iconv(message_text)
      end

      begin
        message.update(:plaintext => message_text) 
      rescue
        log message_text.encoding
        #log message_text
        raise
      end
      @cur_message_id = message.message_id
      message_text
    rescue
      msg = "Error encountered in fetch_and_cache(), message_id #{message_id} [#{@mailbox}]:\n#{$!}\n#{$!.backtrace.join("\n")}" 
      log msg
      msg
    end

    def format_parts_info(parts)
      lines = parts.select {|part| part !~ %r{text/plain}}
      if lines.size > 0
        "\n#{lines.join("\n")}"
      end
    end

  end
end
