require 'sequel'

DB = Sequel.connect 'sqlite://vmail.db'

create_table_script = File.read("db/create.sql")
DB.run create_table_script 

class Vmail::Message < Sequel::Model
#  set_primary_key [:uid, :mailbox]
end
