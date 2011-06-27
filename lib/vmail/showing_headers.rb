module Vmail
  module ShowingHeaders
    # id_set may be a range, array, or string
    def fetch_row_text(id_set, are_uids=false, is_update=false)
      log "Fetch_row_text: #{id_set.inspect}"
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
        error = "Expected fetch results but got nil"
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
      address_struct = if @mailbox == mailbox_aliases['sent'] 
                         structs = envelope.to || envelope.cc
                         structs.nil? ? nil : structs.first 
                       else
                         envelope.from.first
                       end
      address = if address_struct.nil?
                  "Unknown"
                elsif address_struct.name
                  "#{Mail::Encodings.unquote_and_convert_to(address_struct.name, 'UTF-8')} <#{[address_struct.mailbox, address_struct.host].join('@')}>"
                else
                  [Mail::Encodings.unquote_and_convert_to(address_struct.mailbox, 'UTF-8'), Mail::Encodings.unquote_and_convert_to(address_struct.host, 'UTF-8')].join('@') 
                end
      if @mailbox == mailbox_aliases['sent'] && envelope.to && envelope.cc
        total_recips = (envelope.to + envelope.cc).size
        address += " + #{total_recips - 1}"
      end
      date = begin 
               Time.parse(envelope.date).localtime
             rescue ArgumentError
               Time.now
             end

      # TEMPORARY
      # store in sqlite3
      # TODO cache this and check cache before downloading message body
      params = {
        subject: (envelope.subject || ''),
        flags: flags.join(','),
        date: date.to_s,
        size: size,
        sender: address,
        uid: uid,
        mailbox: @mailbox,
        rfc822: @current_mail.to_s,
        plaintext: show_message(uid)
      }
      DB[:messages].insert params
  
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
      log "Error extracting header for uid #{uid} seqno #{seqno}: #$!\n#{$!.backtrace}"
      row_text = "#{seqno.to_s} : error extracting this header"
      {:uid => uid, :seqno => seqno, :row_text => row_text}
    end

    def with_more_message_line(res, start_seqno)
      log "Add_more_message_line for start_seqno #{start_seqno}"
      if @all_search
        return res if start_seqno.nil?
        remaining = start_seqno - 1
      else # filter search
        remaining = (@ids.index(start_seqno) || 1) - 1
      end
      if remaining < 1
        log "None remaining"
        return "Showing all matches\n" + res
      end
      log "Remaining messages: #{remaining}"
      ">  Load #{[100, remaining].min} more messages. #{remaining} remaining.\n" + res
    end

  end
end
