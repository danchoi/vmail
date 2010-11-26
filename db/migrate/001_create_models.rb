class CreateModels < ActiveRecord::Migration
  def self.up
    create_table :messages do |t|
      t.string :sha
      t.integer :sender_id
      t.column :date, :datetime
      t.column :subject, :string
      t.column :eml, :text
    end
    add_index :messages, :sha

    create_table :message_refs do |t|
      t.string :mailbox
      t.integer :uid
      t.integer :message_id
    end
    add_index :message_refs, [:mailbox, :uid]

    create_table :receipts do |t|
      t.integer :message_id
      t.integer :contact_id
    end

    create_table :copyings do |t|
      t.integer :message_id
      t.integer :contact_id
    end

    create_table :contacts do |t|
      t.string :email
      t.string :name
      t.string :domain
    end

  end

  def self.down

    drop_table :contacts

    drop_table :copyings

    drop_table :receipts

    remove_index :message_refs, :column => [:mailbox, :uid]
    drop_table :message_refs

    remove_index :messages, :column => :sha
    drop_table :messages
  end
end

