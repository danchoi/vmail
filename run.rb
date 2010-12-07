require File.expand_path("../lib/lookup_daemon", __FILE__)

# TODO: use gmail.yml
uri = "druby://127.0.0.1:61676"
server = DRbObject.new_with_uri uri
server.select_mailbox ARGV.shift
File.open("mailbox.txt", "w") do |file|
  file.puts server.search(*ARGV)
end
system("DRB_URI='#{uri}' vim -S viewer.vim mailbox.txt")
#server.close
