require 'mail'
require 'open3'

module Vmail
  class MessageFormatter
    # initialize with a Mail object
    def initialize(mail, uid = nil)
      @mail = mail
      @uid = uid
    end

    def list_parts(parts = (@mail.parts.empty? ? [@mail] : @mail.parts))
      lines = parts.map do |part|
        if part.multipart?
          list_parts(part.parts)
        else
          # part.charset could be used
          "- #{part.content_type} #{part.attachment? ? part.filename : ''}"
        end
      end
      lines.flatten
    end

    def plaintext_part(mail=@mail)
      part = find_text_part2(mail.body, mail.content_type)
      if part.nil?
        format_part(@mail || '')
      else
        format_part part
      end
    end

    # helper method
    def find_text_part2(part, content_type)
      if part.multipart?
        part.parts.
          map {|p| find_text_part2(p, p.content_type)}.
          compact.
          select {|p| !p.attachment?}.
          first
      elsif content_type =~ %r[^text/plain] ||
        content_type =~ %r[text/plain] ||
        content_type =~ %r[message/rfc]
        part
      end
    end

    def format_part(part)
      if part && part.respond_to?(:header)
        case part.header["Content-Type"].to_s
        when /text\/html/
          format_html_body(part)
        when /text\/plain/
          format_text_body(part)
        when /message\/rfc/
          m = Mail.new(part.body.decoded)
          plaintext_part(m)
        else # just format_text on it anyway
          format_text_body(part)
        end
      else
        part.decoded.gsub("\r", '')
      end
    rescue
      puts $!
      "[error:] #{$!}"
    end

    def format_text_body(part)
      part.body.decoded.gsub("\r", '')
    end

    # depend on VMAIL_HTML_PART_READER
    # variable
    def format_html_body(part)
      html_tool = ENV['VMAIL_HTML_PART_READER']
      html = part.body.decoded.gsub("\r", '')
      stdin, stdout, stderr = Open3.popen3(html_tool)
      stdin.puts html
      stdin.close
      output = "[vmail: html part translated into plaintext by '#{html_tool}']\n\n" + stdout.read
      charset = part.content_type_parameters && part.content_type_parameters['charset']
      if charset && charset != 'UTF-8'
        output.encode!('utf-8', charset, undef: :replace, invalid: :replace)
      else
        output
      end
    end

    def extract_headers(mail = @mail)
      headers = {
        'from' => utf8(mail['from'].decoded),
        'date' => (mail.date.strftime('%a, %b %d %I:%M %p %Z %Y') rescue mail.date),
        'to' => mail['to'].nil? ? nil : utf8(mail['to'].decoded),
        'cc' => (mail.cc && utf8(mail['cc'].decoded.to_s)),
        'reply_to' => (mail.reply_to && utf8(mail['reply_to'].decoded)),
        'subject' => utf8(mail.subject)
      }
      headers
    rescue
      {'error' => $!}
    end

    def encoding
      @encoding ||= @mail.header.charset || 'UTF-8'
    end

    def utf8(string, this_encoding = encoding)
      return '' unless string
      out = if this_encoding && this_encoding.upcase != 'UTF-8'
              string.encode!('utf-8', this_encoding, undef: :replace, invalid: :replace)
            elsif this_encoding.upcase == 'UTF-8'
              string
            else
              # assume UTF-8 and convert to ascii
              string.encode!('us-ascii', 'utf-8', undef: :replace, invalid: :replace)
            end
      out
    rescue
      $logger.debug $!
      "[error: #$!]"
    end
  end
end
