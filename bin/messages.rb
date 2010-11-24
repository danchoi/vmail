#!/usr/bin/env ruby 

def quote_string(v)
  v.to_s.gsub(/\\/, '\&\&').gsub(/'/, "''")
end

arg = quote_string(ARGV.first)

sql = <<-END
select uid, date, RPAD(sender, 30, " "), subject from messages 
inner join mailboxes on messages.mailbox_id = mailboxes.id
where mailboxes.label = "#{arg}"
order by uid asc
END

cmd = "mysql -uroot gmail -e '#{sql}'"
res = `#{cmd}`
puts res
exit

if res.split("\n").size > 1 
  res = res.split("\n")[1..-1].join("\n") # remove mysql header line
  puts res
end

