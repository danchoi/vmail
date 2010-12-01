require 'mail'
require 'open3'

class MessageFormatter
  # initialize with a raw email
  def initialize(mail)
    @mail = mail
  end

  def list_parts(parts = (@mail.parts.empty? ? [@mail] : @mail.parts))
    if parts.empty?
      return nil
    end
    lines = parts.map do |part|
      if part.multipart?
        list_parts(part.parts)
      else
        # part.charset could be used
        "- #{part.content_type}"
      end
    end
    lines.join("\n")
  end

  def process_body
    part = find_text_part(@mail.parts)
    if part
      if part.header["Content-Type"].to_s =~ /text\/plain/
        format_text_body(part.body) 
      elsif part.header["Content-Type"].to_s =~ /text\/html/
        format_html_body(part.body) 
      end
    else 
      "NO BODY" 
    end
  end

  def find_text_part(parts = @mail.parts)
    if parts.empty?
      return @mail
    end

    part = parts.detect {|part| part.multipart?}
    if part
      find_text_part(part.parts)
    else
      part = parts.detect {|part| (part.header["Content-Type"].to_s =~ /text\/plain/) }
      if part
        return part
      else
        return "no text part"
      end
    end
  end

  def format_text_body(body)
    body.decoded
  end

  # depend on lynx
  def format_html_body(body)
    stdin, stdout, stderr = Open3.popen3("lynx -stdin -dump")
    stdin.puts(body.decoded)
    stdin.close
    stdout.read
  end

  def extract_headers(mail = @mail)
    headers = {'from' => mail.from.first.to_s,
      'date' => mail.date,
      'to' => mail.to.size == 1 ? mail.to[0].to_s : mail.to.map(&:to_s),
      'subject' => mail.subject
    }
    if !mail.cc.nil?
      headers['cc'] = mail.cc.size == 1 ? mail.cc.cc_s : mail.cc.map(&:cc_s)
    end
    if !mail.reply_to.nil?
      headers['reply_to'] = mail.reply_to.size == 1 ? mail.reply_to[0].to_s : mail.reply_to.map(&:reply_to_s)
    end
    headers
  end
end
