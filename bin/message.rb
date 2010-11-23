#!/usr/bin/env ruby 

sql = <<-END
select text from messages where uid = #{ARGV.first}
END

cmd = "mysql -uroot gmail_development -e '#{sql} \\G'"
res = `#{cmd}`

puts res.split("\n")[1..-1].join("\n").sub(/text:\s/, '')
