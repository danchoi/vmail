require 'sequel'

CREATE_TABLE_SCRIPT = File.expand_path("../../../db/create.sql", __FILE__)

if !File.size?('vmail.db')
  puts `sqlite3 vmail.db < #{CREATE_TABLE_SCRIPT}`
end

DB = Sequel.connect 'sqlite://vmail.db'
puts "Connecting to database"
puts "Tables: #{DB.tables}"

if DB[:version].count == 0
  DB[:version].insert(:vmail_version => Vmail::VERSION)
end

module Vmail
  class Message < Sequel::Model(:messages)
    set_primary_key :message_id
    one_to_many :labelings
    many_to_many :labels, :join_table => 'labelings'
  end
end

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

