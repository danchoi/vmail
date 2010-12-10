require 'net/imap'

class ContactsExtractor
  def initialize(config)
    @username, @password = config['login'], config['password']
  end

  def open
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    @imap.login(@username, @password)
    yield @imap
    @imap.close 
    @imap.disconnect
  end

  def extract!
    @contacts = []
    open do |imap|
      mailbox = '[Gmail]/Sent Mail'
      STDERR.puts "selecting #{mailbox}"
      imap.select(mailbox)
      STDERR.puts "fetching last 500 sent messages"
      all_uids = imap.uid_search('ALL')
      limit = [500, all_uids.size].max
      uids = all_uids[-limit ,limit]
      imap.uid_fetch(uids, ["FLAGS", "ENVELOPE"]).each do |fetch_data|
        recipients = fetch_data.attr["ENVELOPE"].to
        next unless recipients
        recipients.each do |address_struct|
          email = [address_struct.mailbox, address_struct.host].join('@') 
          name = address_struct.name
          if name 
            add = "#{name} <#{email}>"
            puts add
          else
            puts email
          end
        end
      end
    end
    @contacts
  end
end

if __FILE__ == $0
  require 'yaml'
  config = YAML::load(File.read(File.expand_path("../../config/gmail.yml", __FILE__)))
  extractor = ContactsExtractor.new(config)
  extractor.extract!
end
