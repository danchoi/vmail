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

        notification_title = "Vmail: "
        notification_body = ""

        if new_ids.size == 1
          # If there is a single email, message is more descriptive about the
          # received email.
          #
          # Example:
          #
          #   (title) Vmail: Colin Sullivan
          #   (body) New Pull request received!
          #
          log "single new message received!"
          new_message = uncached_headers(new_ids)[0]

          # Extract just sender's name from sender field
          notification_title += new_message[:sender].gsub(/\<.*\>/, "").strip()

          # Truncate message subject if necessary
          if new_message[:subject].length > 128
            # Extract first 128 characters from subject of email
            notification_body += new_message[:subject][0..128] + "..."
          else
            notification_body += new_message[:subject]
          end

        else
          # If there are multiple new messages, notification is just a brief
          # listing.
          #
          # Example:
          #
          #   (title)   Vmail: 3 new messages
          #   (body)    Colin Sullivan: New Pull request rec...
          #             Henry Cowell: I am back from the dead!
          #             ...
          #
          log "multiple new messages received!"

          notification_title += new_ids.size.to_s() + " new messages"

          # for each message
          for i in 0...new_ids.size
            new_message = uncached_headers(new_ids)[i]

            # Create message line
            message_line = ""

            # Extract just sender's name from sender field
            message_line += new_message[:sender].gsub(/\<.*\>/, "").strip()

            # Extract subject
            message_line += ": " + new_message[:subject]

            # Concatenate line if necessary
            if message_line.length > 32
              message_line = message_line[0...29] + "..."
            end

            # Add to notification body
            notification_body += message_line + "\n"

          end

          # Concatenate entire notification body if necessary
          if notification_body.length > 128
            notification_body = notification_body[0...125] + "..."
          end

        end

        # Remove any '<>' characters from notification just incase, libnotify
        # can't print '<'
        notification_title = notification_title.tr('<>', '')
        notification_body = notification_body.tr('<>', '')

        @notifier.call notification_title, notification_body

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


