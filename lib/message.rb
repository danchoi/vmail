class Message < ActiveRecord::Base
  has_many :message_refs
  belongs_to :sender, :class_name => "Contact"
  has_many :receipts
  has_many :copyings
  validates_uniqueness_of :sha

  def cache_text
    mail = Mail.new(self.eml)
    body =  mail.parts.detect {|part| part.mime_type == 'text/plain'}
    if body.nil?
      body =  mail.parts.detect {|part| part.mime_type == 'text/html'}
    end
    if body.nil?
      body = mail.body
    end
    output_body = (body ? body.decoded : '') || ''
    # encoding
    begin
      output_body = output_body.gsub( /\r\n/m, "\n" ).gsub(//, "\n")
    rescue
    end
    out = <<-END
    From: #{mail[:from]}
    Date: #{mail[:date]}
      To: #{mail[:to]} 
      Cc: #{mail[:cc]}
 Subject: #{mail[:subject]}
Reply-To: #{mail[:reply_to]}

#{output_body}

END
    update_attribute :text, out
  end

end

