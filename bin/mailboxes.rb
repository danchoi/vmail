#!/usr/bin/env ruby

cmd = "mysql -uroot gmail -e 'select label from mailboxes order by position asc'"
res = `#{cmd}`
res = res.split("\n")[1..-1].join("\n") # remove mysql header line
puts res
