#!/usr/bin/env ruby 

sql = <<-END
select text from messages where uid = #{ARGV.first}
END

cmd = "mysql -uroot gmail_development -e '#{sql} \\G'"
res = `#{cmd}`

puts res.split("\n")[1..-1].join("\n").sub(/text:\s/, '')
exit
if res.split("\n").size > 1 
  res = res.split("\n")[1..-1].join("\n") # remove mysql header line
  puts res.gsub('\\n', "\n")
  
end

