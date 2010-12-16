require 'vmail/message_formatter'
require 'mail'
require 'time'

module Vmail
  class ReplyTemplate

    def initialize(mail, username, name, replyall)
      @username, @name, @replyall = username, name, replyall
      @mail = Mail.new(mail)
    end

    def reply_headers
      formatter = Vmail::MessageFormatter.new(@mail)
      headers = formatter.extract_headers
      subject = headers['subject']
      if subject !~ /Re: /
        subject = "Re: #{subject}"
      end
      date = headers['date'].is_a?(String) ? Time.parse(headers['date']) : headers['date']
      quote_header = "On #{date.strftime('%a, %b %d, %Y at %I:%M %p')}, #{sender} wrote:\n\n"
      body = quote_header + formatter.process_body.gsub(/^(?=>)/, ">").gsub(/^(?!>)/, "> ")
      {'from' => "#@name <#@username>", 'to' => primary_recipient, 'cc' => cc, 'subject' => subject, :body => body}
    end

    # just stick this here
    def forward_headers

    end

    def primary_recipient
      from = @mail.header['from']
      reply_to = @mail.header['reply-to']
      [ reply_to, from ].flatten.compact.map(&:to_s)[0]
    end

    def cc
      return nil unless @replyall
      cc = @mail.header['to'].value.split(/,\s*/) 
      if @mail.header['cc']
        cc += @mail.header['cc'].value.split(/,\s*/) 
      end
      cc = cc.flatten.compact.
        select {|x| 
          x.to_s[/<([^>]+)>/, 1] !~ /#{@username}/ && x.to_s[/^[^<]+/, 1] !~ /#{@name}/
          }.join(', ')
    end

    def sender
      @mail.header['from'].value
    end

    # deprecated
    def address_to_string(x)
      x.name ? "#{x.name} <#{x.mailbox}@#{x.host}>" : "#{x.mailbox}@#{x.host}"
    end

  end
end
