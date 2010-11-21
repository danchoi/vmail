require 'rake'

task :environment do
  require(File.join(File.dirname(__FILE__), 'config', 'environment'))
end

namespace :db do
  desc "Migrate the database"
  task(:migrate => :environment) do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Migration.verbose = true
    ActiveRecord::Migrator.migrate("db/migrate")
  end
end

namespace :gmail do

  desc "Load and create Mailboxes from Gmail account"
  task :mailboxes => :environment do
    Mailbox.create_from_gmail
  end

end
