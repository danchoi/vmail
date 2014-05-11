# encoding: UTF-8
require 'mail'
require 'time'

module Vmail
  module ReplyTemplating

    def reply_template(replyall=false)
      @replyall = replyall
      log "Sending reply template"
      h = reply_headers
      body = h.delete('body')
      format_headers(h) + "\n\n\n" + body + signature
    end

    def reply_headers
      reply_subject = current_message.subject
      if reply_subject !~ /Re: /
        reply_subject = "Re: #{reply_subject}"
      end
      date = DateTime.parse(current_message.date)
      sender = current_message.sender
      reply_quote_header = date ? "On #{date.strftime('%a, %b %d, %Y at %I:%M %p')}, #{sender} wrote:\n\n" : "#{sender} wrote:\n"

      reply_body = reply_quote_header +
        ( current_message.plaintext.split(/^-+$/,2)[1].strip.gsub(/^(?=>)/, ">").gsub(/^(?!>)/, "> ") )

      {
        'references' => current_message.message_id,
	# set 'from' to user-specified value
        'from' => "#@name <#@from>",
        'to' => reply_recipient,
        'cc' => reply_cc,
        'bcc' => @always_bcc,
        'subject' => reply_subject,
        'body' => reply_body
      }
    rescue
      $logger.debug $!
      raise
    end

    def reply_recipient
      current_mail.header['Reply-To'] || current_message.sender
    end

    def reply_cc
      return nil unless (@replyall || @always_cc)
      xs = if @replyall
             ((current_mail['cc'] && current_mail['cc'].decoded) || "") .split(/,\s*/)  + ((current_mail['to'] && current_mail['to'].decoded) || "") .split(/,\s*/)
           else
             []
           end
      xs = xs.select {|x|
        email = (x[/<([^>]+)>/, 1] || x)
        email !~ /#{reply_recipient}/ \
          && email !~ /#@username/ \
          && (@always_cc ? (email !~ /#{@always_cc}/) : true)
      }
      if @always_cc
        xs << @always_cc
      end
      xs.uniq.select {|x| x != reply_recipient }.join(', ')
    end

  end
end
