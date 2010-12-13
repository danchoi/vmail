require 'net/imap'

module Vmail
class ContactsExtractor
  def initialize(username, password)
    puts "logging as #{username}"
    @username, @password = username, password
  end

  def open
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    puts @imap.login(@username, @password)
    yield @imap
    @imap.close 
    @imap.disconnect
  end

  def extract(limit = 500)
    open do |imap|
      mailbox = '[Gmail]/Sent Mail'
      STDERR.puts "selecting #{mailbox}"
      imap.select(mailbox)
      STDERR.puts "fetching last #{limit} sent messages"
      all_uids = imap.uid_search('ALL')
      STDERR.puts "total messages: #{all_uids.size}"
      limit = [limit, all_uids.size].min
      STDERR.puts "extracting addresses from #{limit} of them"
      uids = all_uids[-limit ,limit]
      imap.uid_fetch(uids, ["FLAGS", "ENVELOPE"]).each do |fetch_data|
        recipients = fetch_data.attr["ENVELOPE"].to
        next unless recipients
        recipients.each do |address_struct|
          email = [address_struct.mailbox, address_struct.host].join('@') 
          name = address_struct.name
          if name 
            name = Mail::Encodings.unquote_and_convert_to(name, 'utf-8') 
            yield "#{name} <#{email}>"
          else
            yield email
          end
        end
      end
    end
  end
end
end

