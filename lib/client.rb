require 'drb'

server = DRbObject.new_with_uri ARGV.shift
method = ARGV.shift

if method == 'deliver' || method == 'save_draft'
  text = STDIN.read
  puts server.send(method, text)
else
  puts server.send(method, *ARGV)
end

