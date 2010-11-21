class CreateModels < ActiveRecord::Migration
  def self.up
    create_table :messages do |t|
      t.column :uid, :integer, :null => false
      t.column :sender, :string
      t.column :date, :datetime
      t.column :subject, :string
      t.column :recipients, :text
      t.column :text, :text
      t.column :eml, :text
    end

    add_index :messages, :uid

    create_table :mailboxes do |t|
      t.integer :position
      t.string :label, :null => false, :unique => true
    end

    create_table :mailboxes_messages, :id => false do |t|
      t.integer :mailbox_id, :null => false
      t.integer :message_id, :null => false
    end
  end

  def self.down
    drop_table :mailboxes_messages

    drop_table :mailboxes

    drop_table :messages
  end
end

