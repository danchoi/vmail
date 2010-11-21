require File.expand_path('../../config/environment', __FILE__)

mailbox_name, uid, gmail_label = *ARGV

mailbox = Mailbox.find_by_label(mailbox_name)

puts mailbox.label_message(uid.to_i, gmail_label)



