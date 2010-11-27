require 'drb'

url = "druby://127.0.0.1:61676"
server = DRbObject.new_with_uri(url)
method = ARGV.shift
puts server.send(method, *ARGV)

