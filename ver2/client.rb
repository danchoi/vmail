require 'drb'
require 'net/imap'
x = DRbObject.new_with_uri 'druby://localhost:3030'
