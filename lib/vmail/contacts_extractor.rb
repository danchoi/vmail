require 'net/imap'

module Vmail
class ContactsExtractor

  def initialize(config)
    @config = config
    @host = @config['server'] || 'imap.gmail.com'
    @port = @config['port'] || 993
    @sent_folder = @config['folder_sent'] || 'Sent Mail'
    @username = @config['username']
    @password = @config['password']
    @prefix = ''
    puts "Logging as #@username at #@host"
  end

  def open
    @imap = Net::IMAP.new(@host, @port, true, nil, false)
    puts @imap.login(@username, @password)
    yield @imap
    @imap.close 
    @imap.disconnect
  end

  def extract(limit = 500)
    open do |imap|
      set_mailbox_prefix
      mailbox = "#@prefix#@sent_folder"
      STDERR.puts "Selecting #{mailbox}"
      imap.select(mailbox)
      STDERR.puts "Fetching last #{limit} sent messages"
      all_uids = imap.uid_search('ALL')
      STDERR.puts "Total messages: #{all_uids.size}"
      limit = [limit, all_uids.size].min
      STDERR.puts "Extracting addresses from #{limit} of them"
      uids = all_uids[-limit ,limit]
      imap.uid_fetch(uids, ["FLAGS", "ENVELOPE"]).each do |fetch_data|
        recipients = fetch_data.attr["ENVELOPE"].to
        next unless recipients
        recipients.each do |address_struct|
          email = [address_struct.mailbox, address_struct.host].join('@') 
          name = address_struct.name
          if name 
            name = Mail::Encodings.unquote_and_convert_to(name, 'UTF-8') 
            yield %Q("#{name}" <#{email}>)
          else
            yield email
          end
        end
      end
    end
  end

  def set_mailbox_prefix
    mailboxes = ((@imap.list("[#@prefix]/", "%") || []) + (@imap.list("", "*")) || []).map {|struct| struct.name}
    if !@config['server']
      @prefix = mailboxes.detect {|m| m =~ /^\[Google Mail\]/}  ?  "[Google Mail]/" : "[Gmail]/"
    end
  end
end
end

