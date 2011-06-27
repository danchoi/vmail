require 'sequel'

DB = Sequel.connect 'sqlite://vmail.db'

create_table_script = File.read("db/create.sql")
DB.run create_table_script 

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


