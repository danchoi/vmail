require 'sequel'

# check database version

CREATE_TABLE_SCRIPT = File.expand_path("../../../db/create.sql", __FILE__)
print "Checking vmail.db version... "
db = Sequel.connect 'sqlite://vmail.db'
if db.tables.include?(:version) &&
    (r = db[:version].first) &&
    r[:vmail_version] != Vmail::VERSION

  print "Vmail database version is outdated. Recreating.\n"
  `rm vmail.db`
  `sqlite3 vmail.db < #{CREATE_TABLE_SCRIPT}`
else
  print "OK\n"
end
db.disconnect

if !File.size?('vmail.db')
  puts `sqlite3 vmail.db < #{CREATE_TABLE_SCRIPT}`
end

DB = Sequel.connect 'sqlite://vmail.db'
puts "Connecting to database"

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

