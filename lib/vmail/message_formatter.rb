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

    def process_body
      part = find_text_part(@mail.parts)
      body = if part && part.respond_to?(:header)
        if part.header["Content-Type"].to_s =~ /text\/plain/
          format_text_body(part) 
        elsif part.header["Content-Type"].to_s =~ /text\/html/
          format_html_body(part) 
        else
          format_text_body(part) 
        end
      else 
        "NO BODY" 
      end
    rescue
      puts $!
      body
    end

    def find_text_part(parts = @mail.parts)
      if parts.empty?
        return @mail
      end
      part = parts.detect {|part| part.multipart?}
      if part
        find_text_part(part.parts)
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
      charset = part.content_type_parameters && part.content_type_parameters['charset']
      if charset
        Iconv.conv('utf-8//translit//ignore', charset, text)
      else
        text
      end
    end

    # depend on lynx
    def format_html_body(part)
      html = part.body.decoded.gsub("\r", '')
      stdin, stdout, stderr = Open3.popen3("lynx -stdin -dump")
      stdin.puts html
      stdin.close
      output = stdout.read
      charset = part.content_type_parameters && part.content_type_parameters['charset']
      charset ?  Iconv.conv('utf-8//translit//ignore', charset, output) : output
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
      @encoding ||= @mail.header.charset || 'utf-8'
    end

    def utf8(string)
      return '' unless string
      return string unless encoding
      Iconv.conv('utf-8//translit/ignore', encoding, string)
    rescue
      puts $!
      string
    end
  end
end
