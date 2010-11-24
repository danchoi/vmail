#!/usr/bin/env ruby 

def quote_string(v)
  v.to_s.gsub(/\\/, '\&\&').gsub(/'/, "''")
end

mailbox = quote_string(ARGV[0])
query = quote_string(ARGV[1])

sql = <<-END
select uid, date, RPAD(sender, 30, " "), subject from messages 
inner join mailboxes on messages.mailbox_id = mailboxes.id
where mailboxes.label = "#{mailbox}"
and (messages.subject LIKE "%#{query}%" or messages.sender LIKE "%#{query}%")
order by uid asc
END

cmd = "mysql -uroot gmail -e '#{sql}'" # | sed -n -e '2,$p'"
res = `#{cmd}`
puts res
