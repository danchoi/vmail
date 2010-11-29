#!/usr/bin/env ruby

require File.expand_path('../lib/lookup_daemon', __FILE__)

mailbox = ARGV.shift
pid = Process.fork do 

  GmailServer.daemon
  GmailServer.start

end
sleep 3
puts `ruby lib/client.rb select_mailbox '#{mailbox}'`
puts `ruby lib/client.rb search #{ARGV.join(' ')} > out`

system("vim -S viewer.vim out")
Process.kill "HUP", pid


