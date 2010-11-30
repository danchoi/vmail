require File.expand_path("../lib/lookup_daemon", __FILE__)

uri= GmailServer.daemon

puts "using url #{uri}"
#url = "druby://127.0.0.1:61676"
server = DRbObject.new_with_uri uri
server.select_mailbox ARGV.shift
File.open("mailbox.txt", "w") do |file|
  file.puts uri
  file.puts server.search(*ARGV)
end
system("vim -S viewer.vim mailbox.txt")
server.close
