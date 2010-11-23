require File.expand_path('../../config/environment', __FILE__)

label = ARGV.first
mailbox = Mailbox.find_by_label label

puts "Updating #{label}"
mailbox.update_from_gmail :num_messages => 200

