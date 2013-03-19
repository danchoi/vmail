require "vmail/imap_client"

module Vmail
  class InboxPoller < ImapClient


    # This is a second IMAP client operating in a separate process
 
    def start_polling
      n = [`which notify-send`.chomp, `which growlnotify`.chomp].detect {|c| c != ''}
      if n
        log "Using notify tool: #{n}"
        @notifier = case n
          when /notify-send/
            Proc.new {|t, m| `#{n} -t 6000000 '#{t}' '#{m}'` }
          when /growlnotify/
            Proc.new {|t, m| `#{n} -t '#{t}' -m '#{m}'` }
          end
      else
        log "No notification tool detected. INBOX polling aborted."
        return
      end
     
      sleep 30
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
        @ids = @ids + new_ids
	# remove '<>' from email. libnotify can't print '<' 
        res = uncached_headers(new_ids).map {|m| m[:sender] }.join(", ").tr('<>','')
        @notifier.call "Vmail: new email", "from " + res
      end
    rescue
      log "VMAIL_ERROR: #{[$!.message, $!.backtrace].join("\n")}"
    end

    # doesn't try to access Sequel / sqlite3
    def uncached_headers(id_set)
      log "Fetching headers for #{id_set.size} messages"
      results = reconnect_if_necessary do 
        @imap.fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID"])
      end
      results.reverse.map do |x| 
        envelope = x.attr["ENVELOPE"]
        message_id = envelope.message_id
        subject = Mail::Encodings.unquote_and_convert_to((envelope.subject || ''), 'UTF-8')
        recipients = ((envelope.to || []) + (envelope.cc || [])).map {|a| extract_address(a)}.join(', ')
        sender = extract_address envelope.from.first
        uid = x.attr["UID"]
        params = {
          subject: (subject || ''),
          flags: x.attr['FLAGS'].join(','),
          date: Time.parse(envelope.date).localtime.to_s,
          size: x.attr['RFC822.SIZE'],
          sender: sender,
          recipients: recipients
        }
      end
    end

    def log(string)
      if string.is_a?(::Net::IMAP::TaggedResponse)
        string = string.raw_data
      end
      @logger.debug "[INBOX POLLER]: #{string}"
    end


  end
end


