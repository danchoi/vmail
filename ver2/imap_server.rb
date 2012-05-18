require 'drb'
require 'net/imap'
require 'yaml'

config = YAML::load_file(ARGV.first)
puts config.inspect
username, password = config['username'], config['password']
name = config['name']
signature = config['signature']
always_cc = config['always_cc']
always_bcc = config['always_bcc']
mailbox = nil
imap_server = config['server'] || 'imap.gmail.com'
imap_port = config['port'] || 993
# generic smtp settings
smtp_server = config['smtp_server'] || 'smtp.gmail.com'
smtp_port = config['smtp_port'] || 587
smtp_domain = config['smtp_domain'] || 'gmail.com'
authentication = config['authentication'] || 'plain'

imap = Net::IMAP.new(imap_server, imap_port, true, nil, false)
puts imap.login(username, password)

drb = DRb.start_service('druby://localhost:3030', imap)
puts "Starting DRb on #{drb.uri}"
DRb.thread.join


