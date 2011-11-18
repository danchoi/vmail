module Vmail
  class InboxPoller < ImapClient

    # This is a second IMAP client operating in a separate process
 
    def start_polling
      n = [`which notify-send`.chomp, `which growlnotify`.chomp].detect {|c| c != ''}
      if n
        log "Using notify tool: #{n}"
        @notifier = case n
          when /notify-send/
            Proc.new {|t, m| `#{n} '#{t}' '#{m}'` }
          when /growlnotify/
            Proc.new {|t, m| `#{n} -t '#{t}' -m '#{m}'` }
          end
      else
        log "No notification tool detected. INBOX polling aborted."
        return
      end
     
      log "INBOX POLLER: started polling"
      @mailboxes.unshift "INBOX"
      select_mailbox "INBOX"
      search "ALL"
      loop do
        log "INBOX POLLER: checking inbox"
        update
        sleep 30
      end
    end

    def update
      new_ids = check_for_new_messages 
      if !new_ids.empty?
        self.max_seqno = new_ids[-1]
        @ids = @ids + new_ids
        message_ids = fetch_and_cache_headers(new_ids)
        res = get_message_headers(message_ids)
        @notifier.call "Vmail: new email", "from #{res}"
      end
    rescue
      log "VMAIL_ERROR: #{[$!.message, $!.backtrace].join("\n")}"
    end

    def get_message_headers(message_ids)
      messages = message_ids.map {|message_id| 
        m = Message[message_id]
        if m.nil?
          raise "Message #{message_id} not found"
        end
        m
      }
      res = messages.map {|m| m.sender }.join(", ")
      res
    end

    def log(string)
      if string.is_a?(::Net::IMAP::TaggedResponse)
        string = string.raw_data
      end
      @logger.debug "[INBOX POLLER]: #{string}"
    end


  end
end


