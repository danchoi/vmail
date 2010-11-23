#!/usr/bin/env ruby 
def quote_string(v)
  v.to_s.gsub(/\\/, '\&\&').gsub(/'/, "''")
end

sql = <<-END
select text from messages where uid = #{ARGV[1]} and mailbox_id = (select mailboxes.id from mailboxes where mailboxes.label = "#{quote_string ARGV[0]}")
END

puts sql

cmd = "mysql -uroot gmail -e '#{sql} \\G'"
res = `#{cmd}`

begin
  puts res.split("\n")[1..-1].join("\n").sub(/text:\s/, '')
rescue ArgumentError
  puts res
end
