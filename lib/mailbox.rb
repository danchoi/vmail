class Mailbox < ActiveRecord::Base
  has_and_belongs_to_many :messages

  def self.create_from_gmail
    found = []
    $gmail.mailboxes.
      select {|box| !box.attr.include?(:Noselect)}.
      each_with_index do |box, index|
        mailbox = Mailbox.find_or_create_by_label box.name
        mailbox.update_attribute :position, index
        found << mailbox
      end
    found.each {|m| puts "- #{m.label}"}
    (Mailbox.all - found).each do |mailbox|
      puts "Destroying #{mailbox.label}"
      mailbox.destroy
    end
  end

  def update_from_gmail
  end
end


