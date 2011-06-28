module Vmail
  module ShowingHeaders

    def get_message_headers(message_ids)
      messages = message_ids.map {|message_id| Message[message_id] }
      messages.map {|m| format_header_for_list(m)}.join("\n")
    end

    def fetch_and_cache_headers(id_set)
      log "Fetching headers for #{id_set.size} messages"
      results = reconnect_if_necessary do 
        @imap.fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID"])
      end
      results.reverse.map do |x| 
        envelope = x.attr["ENVELOPE"]
        message_id = envelope.message_id
        subject = Mail::Encodings.unquote_and_convert_to(envelope.subject, 'UTF-8')
        recipients = ((envelope.to || []) + (envelope.cc || [])).map {|a| extract_address(a)}.join(', ')
        sender = extract_address envelope.from.first
        uid = x.attr["UID"]
        message = Message[message_id]
        unless message
          message = Message.new
          message.message_id = message_id
          message.save
        end
        params = {
          subject: (subject || ''),
          flags: x.attr['FLAGS'].join(','),
          date: DateTime.parse(envelope.date).to_s,
          size: x.attr['RFC822.SIZE'],
          sender: sender,
          recipients: recipients
        }
        # We really just need to update the flags, buy let's update everything
        message.update params

        unless message.labels.include?(@label)
          params = {message_id: message.message_id, uid: uid, label_id: @label.label_id}

          Labeling.create params
        end
        message_id
      end
    end

    def extract_address(address_struct)
      address = if address_struct.nil?
                  "Unknown"
                elsif address_struct.name
                  "#{Mail::Encodings.unquote_and_convert_to(address_struct.name, 'UTF-8')} <#{[address_struct.mailbox, address_struct.host].join('@')}>"
                else
                  [Mail::Encodings.unquote_and_convert_to(address_struct.mailbox, 'UTF-8'), Mail::Encodings.unquote_and_convert_to(address_struct.host, 'UTF-8')].join('@') 
                end

    end

    def format_header_for_list(message)
      date = DateTime.parse(message.date)
      formatted_date = if date.year != Time.now.year
                         date.strftime "%b %d %Y" 
                       else 
                         date.strftime "%b %d %I:%M%P"
                       end
      address = if @mailbox == mailbox_aliases['sent']
                  message.recipients
                else
                  message.sender
                end

      mid_width = @width - 38
      address_col_width = (mid_width * 0.3).ceil
      subject_col_width = (mid_width * 0.7).floor
      row_text = [ format_flags(message.flags).col(2),
                   (formatted_date || '').col(14),
                   address.col(address_col_width),
                   message.subject.col(subject_col_width), 
                   number_to_human_size(message.size).rcol(7), 
                   message.message_id ].join(' | ')
    end

    FLAGMAP = {'Flagged' => '*', 'Answered' => 'A'}

    def format_flags(flags)
      # other flags like "Old" should be hidden here
      flags = flags.split(',').map {|flag| FLAGMAP[flag] || flag}
      flags.delete("Old")
      if flags.delete('Seen').nil?
        flags << '+' # unread
      end
      flags.join('')
    end

    def with_more_message_line(res)
      remaining = @start_index 
      if remaining < 1
        return res
      end
      res + "\n>  Load #{[100, remaining].min} more messages. #{remaining} remaining." 
    end

  end
end
