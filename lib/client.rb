require 'drb'

server = DRbObject.new_with_uri ARGV.shift
method = ARGV.shift

if method == 'deliver'
  text = STDIN.read
  puts server.send(method, text)
elsif method == 'parsed_search'
  mailbox_chunks = []
  while (chunk = ARGV.shift) !~ /^\d+$/
    mailbox_chunks << chunk
    break if ARGV.empty?
  end
  mailbox = mailbox_chunks.join(' ')
  server.select_mailbox mailbox
  puts server.search chunk, *ARGV
else
  puts server.send(method, *ARGV)
end

