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


desc "Load and create Mailboxes from Gmail account"
task :make_mailboxes => :environment do
  Mailbox.create_from_gmail
end

desc "List Mailboxes"
task :list_mailboxes => :environment do
  Mailbox.all.each {|x| puts "- #{x.label}"}
end

desc "Update from Gmail"
task :update => :environment do
  label = ENV['BOX'] || ENV['MAILBOX']
  mailbox = Mailbox.find_by_label label
  raise "Can't find mailbox" unless mailbox
  mailbox.update_from_gmail
end

