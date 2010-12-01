require 'mail'
require 'open3'

class MessageFormatter
  # initialize with a Mail object
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
      headers['cc'] = mail.cc.size == 1 ? mail.cc[0].to_s : mail.cc.map(&:to_s)
    end
    if !mail.reply_to.nil?
      headers['reply_to'] = mail.reply_to.size == 1 ? mail.reply_to[0].to_s : mail.reply_to.map(&:reply_to_s)
    end
    headers
  end

  def encoding
    @mail.encoding
  end

  # address method could be 'to' for sent messages
  def summary(uid, flags, address_method = 'from') 
    address = @mail.send(address_method)
    address = address.size == 1 ? address[0].to_s.encode('utf-8') : address.map {|a| a.to_s.encode('utf-8')} 
    "#{uid} #{format_time(@mail.date.to_s)} #{address[0,30].ljust(30)} #{@mail.subject.encode('utf-8')[0,70].ljust(70)} #{flags.inspect.col(30)}"
  end

  def format_time(x)
    Time.parse(x.to_s).localtime.strftime "%D %I:%M%P"
  end

end