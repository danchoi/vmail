class CreateModels < ActiveRecord::Migration
  def self.up
    create_table :messages do |t|
      t.column :uid, :integer, :null => false
      t.integer :mailbox_id, :null => false
      t.column :sender, :string
      t.column :date, :datetime
      t.column :subject, :string
      t.column :recipients, :text
      t.column :text, :text
      t.column :eml, :text
    end

    add_index :messages, [:uid, :mailbox_id]

    create_table :mailboxes do |t|
      t.integer :position
      t.string :label, :null => false, :unique => true
    end

  end

  def self.down
    drop_table :mailboxes

    drop_table :messages
  end
end

