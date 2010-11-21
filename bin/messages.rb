#!/usr/bin/ruby 
# install these gems
# dbd-mysql
require "dbi"

DBI.connect("DBI:Mysql:gmail_development", "root", "") do |handler|

  sql = <<-END
select uid, sender, subject from messages 
inner join mailboxes_messages mm on messages.id = mm.message_id
inner join mailboxes on mm.mailbox_id = mailboxes.id
where mailboxes.label = ? 
  END

  handler.select_all(sql, ARGV.first) do | row |
    uid, sender, subject = *row
    p "%.30s %s %s" % [sender.ljust(30), subject, uid]
  end

end

