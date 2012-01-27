require 'min_mail/version'
require 'min_mail/imap'
require 'mail'
require 'time'

module MinMail
    def self.extract_address(address_struct)
      address = if address_struct.nil?
                  "Unknown"
                else 
                  email = [ (address_struct.mailbox ? Mail::Encodings.unquote_and_convert_to(address_struct.mailbox, 'UTF-8') : ""), 
                      (address_struct.host ?  Mail::Encodings.unquote_and_convert_to(address_struct.host, 'UTF-8'): "")
                    ].join('@') 
                  if address_struct.name
                   "#{Mail::Encodings.unquote_and_convert_to((address_struct.name || ''), 'UTF-8')} <#{email}>"
                  else
                    email
                  end
                end

    end


  def self.start

    config = YAML::load File.read(ENV['HOME'] + "/vmail/.vmailrc")

    Imap.new(config).with_open {|imap|
      imap.select "INBOX"
      ids = imap.search("all")
      ids.reverse!
      results = imap.fetch(ids[0,20], ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID"])
      results.map { |x| 

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
        puts params.inspect
      }
    }
    
  end
end

if __FILE__ == $0
  MinMail.start
end
