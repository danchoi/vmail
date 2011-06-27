module Vmail
  module ShowingMessage
    # holds mail objects keyed by [mailbox, uid]
    def cached_full_message?(uid)
      m = Message[uid: uid, mailbox: @mailbox]
      m && !m.plaintext.nil?
    end

    def show_message(uid, raw=false)
      log "Show message: #{uid}"
      return @current_mail.to_s if raw 
      uid = uid.to_i
      if uid == @current_message_uid 
        return @current_message 
      end

      log "Showing message uid: #{uid}"
      data = if x = cached_full_message?(uid)
               log "- message cache hit"
               x
             else 
               log "- fetching and storing to sqlite"
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
      log "Parsing error"
      "Error encountered parsing this message:\n#{$!}\n#{$!.backtrace.join("\n")}"
    end

    def fetch_and_cache(uid)
      if data = cached_full_message?(uid)
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
      seqno = fetch_data.seqno
      rfc822 = Mail.new(fetch_data.attr['RFC822'])
      
      formatter = Vmail::MessageFormatter.new rfc822

      message_text = <<-EOF
#{@mailbox} uid:#{uid} #{number_to_human_size size} #{flags.inspect} #{format_parts_info(formatter.list_parts)}
#{divider '-'}
#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
      d = {:mail => mail, :size => size, :message_text => message_text, :seqno => seqno, :flags => flags}

    rescue
      msg = "Error encountered parsing message uid  #{uid}:\n#{$!}\n#{$!.backtrace.join("\n")}" + 
        "\n\nRaw message:\n\n" + mail.to_s
      log msg
      {:message_text => msg}
    end

    def format_parts_info(parts)
      lines = parts.select {|part| part !~ %r{text/plain}}
      if lines.size > 0
        "\n#{lines.join("\n")}"
      end
    end

  end
end
