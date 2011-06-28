require 'sequel'

DB = Sequel.connect 'sqlite://vmail.db'

create_table_script = File.expand_path("../db/create.sql", __FILE__)

if !File.exists?("vmail.db")
  DB.run create_table_script 
end

if DB[:version].count == 0
  DB[:version].insert(:vmail_version => Vmail::VERSION)
end

class Vmail::Message < Sequel::Model
  set_primary_key :message_id
  one_to_many :labelings
  many_to_many :labels, :join_table => 'labelings'
end

class Vmail::Label < Sequel::Model
  set_primary_key :label_id
  one_to_many :labelings
  many_to_many :messages, :join_table => 'labelings'
end

class Vmail::Labeling < Sequel::Model
end


