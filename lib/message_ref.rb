class MessageRef < ActiveRecord::Base
  validates_uniqueness_of :uid, :scope => :mailbox
  belongs_to :message
end
