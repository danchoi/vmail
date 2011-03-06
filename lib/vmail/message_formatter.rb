require 'mail'
require 'open3'
require 'iconv'

module Vmail
  class MessageFormatter
    # initialize with a Mail object
    def initialize(mail, uid = nil)
      @mail = mail
      @uid = uid
    end

    def list_parts(parts = (@mail.parts.empty? ? [@mail] : @mail.parts))
      if parts.empty?
        return []
      end
      lines = parts.map do |part|
        if part.multipart?
          list_parts(part.parts)
        else
          # part.charset could be used
          "- #{part.content_type}"
        end
      end
      lines.flatten
    end

    def process_body(target = @mail)
      out = if target.header['Content-Type'].to_s =~ /multipart\/mixed/
        target.parts.map {|part| 
          if part.multipart?
            part = find_text_or_html_part(target.parts)
            format_part(part) 
          else
            format_part(part) 
          end
        }.join("\n#{'-' * 39}\n")
      elsif target.header['Content-Type'].to_s =~ /multipart\/alternative/
        part = find_text_or_html_part(target.parts)
        format_part(part) 
      else
        format_part(target)
      end
      out
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
          process_body(m)
        else # just format_text on it anyway
          format_text_body(part) 
        end
      else 
        "[NO BODY]" 
      end
    rescue
      puts $!
      "[error:] #{$!}"
    end

    def find_text_or_html_part(parts = @mail.parts)
      if parts.empty?
        return @mail
      end
      part = parts.detect {|part| part.multipart?}
      if part
        find_text_or_html_part(part.parts)
      else
        # no multipart part
        part = parts.detect {|part| (part.header["Content-Type"].to_s =~ /text\/plain/) }
        if part
          return part
        else
          parts.first
        end
      end
    end

    def format_text_body(part)
      text = part.body.decoded.gsub("\r", '')
      charset = (part.content_type_parameters && part.content_type_parameters['charset']) || encoding
      if (charset && charset != 'UTF-8') 
        text.force_encoding(charset)
      else
        text
      end
      text.encode("UTF-8", undef: :replace, replace: "??", invalid: :replace)
    end

    # depend on lynx or whatever is set by the VMAIL_HTML_PART_READER
    # variable
    def format_html_body(part)
      html_tool = ENV['VMAIL_HTML_PART_READER'] || 'lynx -stdin -dump'
      html = part.body.decoded.gsub("\r", '')
      stdin, stdout, stderr = Open3.popen3(html_tool)
      stdin.puts html
      stdin.close
      output = "[vmail: html part translated into plaintext by '#{html_tool}']\n\n" + stdout.read
      charset = part.content_type_parameters && part.content_type_parameters['charset']
      if charset && charset != 'UTF-8'
        Iconv.conv('UTF-8//TRANSLIT//IGNORE', charset, output) 
      else
        output
      end
    end

    def extract_headers(mail = @mail)
      headers = {'from' => utf8(mail['from'].decoded),
        'date' => (mail.date.strftime('%a, %b %d %I:%M %p %Z %Y') rescue mail.date),
        'to' => mail['to'].nil? ? nil : utf8(mail['to'].decoded),
        'subject' => utf8(mail.subject)
      }
      if !mail.cc.nil?
        headers['cc'] = utf8(mail['cc'].decoded.to_s)
      end
      if !mail.reply_to.nil?
        headers['reply_to'] = utf8(mail['reply_to'].decoded)
      end
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
              Iconv.conv('UTF-8//TRANSLIT/IGNORE', this_encoding, string)
            elsif this_encoding.upcase == 'UTF-8' 
              string 
            else
              # assume UTF-8
              Iconv.conv('US-ASCII//TRANSLIT/IGNORE', 'UTF-8', string)
            end
      out
    rescue
      "[error: #$!]"
    end
  end
end
