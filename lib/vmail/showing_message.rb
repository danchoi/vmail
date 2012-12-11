# encoding: UTF-8

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
      if m
        log "- found message #{message_id}"
        log "- message has plaintext? #{!m.plaintext.nil?}"
      else
        log "- could not find message #{message_id.inspect}"
      end
      m && !m.plaintext.nil? && m
    end

    def show_message(message_id, raw=false)
      message_id = message_id.strip.gsub('\\', '')
      log "Show message: #{message_id.inspect}"
      return current_message.rfc822 if raw 
      res = retry_if_needed { fetch_and_cache(message_id) }
      log "Showing message message_id: #{message_id}"
      @cur_message_id = message_id
      res
    end

    def fetch_and_cache(message_id)
      if message = cached_full_message?(message_id)
        log "- full message cache hit"        
        return message.plaintext
      end
      log "- full message cache miss"        
      labeling = Labeling[message_id: message_id, label_id: @label.label_id]
      uid = labeling.uid

      log "- fetching message uid #{uid}"        
      fetch_data = reconnect_if_necessary do 
        res = retry_if_needed do
          @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        end
        raise "Message uid #{uid} could not be fetched from server" if res.nil?
        res[0] 
      end
      seqno = fetch_data.seqno
      rfc822 = Mail.new(fetch_data.attr['RFC822'])
      formatter = Vmail::MessageFormatter.new rfc822

      message = Message[message_id]
      parts_list = format_parts_info(formatter.list_parts)
      headers_hash = formatter.extract_headers
      headers_hash['date'] 
      headers = format_headers headers_hash
      # replace the date value with the one derived from the envelope
      body = formatter.plaintext_part
      conv_from = /charset=(.*)\s/.match(parts_list)[1].strip
      body.force_encoding conv_from
      body = body.encode!('utf-8', undef: :replace, invalid: :replace)
      message_text = <<-EOF
#{message_id} #{number_to_human_size message.size} #{message.flags} #{parts_list}
#{divider '-'}
#{headers}

#{body}
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
      message_text
    rescue
      msg = "Error encountered in fetch_and_cache(), message_id #{message_id} [#{@mailbox}]:\n#{$!}\n#{$!.backtrace.join("\n")}" 
      log msg
      msg
    end

    def format_parts_info(parts)
      lines = parts #.select {|part| part !~ %r{text/plain}}
      if lines.size > 0
        "\n#{lines.join("\n")}"
      end
    end

  end
end
