module Vmail
  module ShowingMessage
    # holds mail objects keyed by [mailbox, uid]
    def cached_full_message?(uid)
      m = Message[uid: uid, mailbox: @mailbox]
      m && !m.plaintext.nil?
    end

    def show_message(uid, raw=false)
      uid = uid.to_i
      log "Show message: #{uid}"
      return @current_message.rfc822 if raw 
      log "Showing message uid: #{uid}"
      res = fetch_and_cache(uid)
      if res.nil?
        # retry, though this is a hack!
        log "- data is nil. retrying..."
        return show_message(uid, raw)
      end
      res
    end

    def fetch_and_cache(uid)
      if data = cached_full_message?(uid)
        log "- full message cache hit"        
        return data
      end
      log "- full message cache miss"        
      fetch_data = reconnect_if_necessary do 
        res = @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        if res.nil?
          # retry one more time ( find a more elegant way to do this )
          res = @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        end
        res[0] 
      end
      seqno = fetch_data.seqno
      rfc822 = Mail.new(fetch_data.attr['RFC822'])
      formatter = Vmail::MessageFormatter.new rfc822

      message = Message[uid: uid, mailbox: @mailbox]
      message_text = <<-EOF
#{@mailbox} uid:#{uid} #{number_to_human_size message.size} #{message.flags} #{format_parts_info(formatter.list_parts)}
#{divider '-'}
#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
      # FIXME error is no primary key associated with model
      # /home/choi/.rvm/gems/ruby-1.9.2-p180@vmail/gems/sequel-3.24.1/lib/sequel/model/base.rb:982:in `pk'
      # /home/choi/.rvm/gems/ruby-1.9.2-p180@vmail/gems/sequel-3.24.1/lib/sequel/model/base.rb:991

      @current_message = message.update (
        :rfc822 => rfc822,
        :plaintext => message_text
      )
      message_text
    rescue
      msg = "Error encountered parsing message uid #{uid} [#{@mailbox}]:\n#{$!}\n#{$!.backtrace.join("\n")}" 
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
