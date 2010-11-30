require 'drb'

server = DRbObject.new_with_uri ARGV.shift
method = ARGV.shift
puts server.send(method, *ARGV)

