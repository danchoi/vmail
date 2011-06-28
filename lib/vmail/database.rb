require 'sequel'

if !File.size?('vmail.db')
  create_table_script = File.expand_path("../../../db/create.sql", __FILE__)
  puts `sqlite3 vmail.db < #{create_table_script}`
end

DB = Sequel.connect 'sqlite://vmail.db'

if DB[:version].count == 0
  DB[:version].insert(:vmail_version => Vmail::VERSION)
end

module Vmail
  class Message < Sequel::Model(:messages)
    set_primary_key :message_id
    one_to_many :labelings
    many_to_many :labels, :join_table => 'labelings'
  end

  class Label < Sequel::Model(:labels)
    set_primary_key :label_id
    one_to_many :labelings
    many_to_many :messages, :join_table => 'labelings'
  end

  class Labeling < Sequel::Model(:labelings)
  end
end

