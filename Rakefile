require 'rake'
require 'rake/testtask'

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

  desc "drop and recreate db"
  task :recreate do 
    system "mysqladmin -uroot drop gmail"
    system  "mysqladmin -uroot create gmail"
    Rake::Task['db:migrate'].invoke
  end
end

desc "List Mailboxes"
task :list_mailboxes => :environment do
  $gmail.mailboxes.each {|x| puts "- #{x}"}
end

desc "Update from Gmail"
task :update => :environment do
  mailbox = ENV['BOX'] || ENV['MAILBOX'] || 'inbox'
  puts "using #{mailbox}" 
  $gmail.mailbox(mailbox).fetch do |imap, uids|
    uids.each do |uid|
      email = imap.uid_fetch(uid, "RFC822")[0].attr["RFC822"]
      puts email.to_s
    end
  end
end

desc "Run tests"
task :test => :environment do 
  $:.unshift File.expand_path("test")
  require 'test_helper'
  require 'time_format_test'
  require 'message_formatter_test'
  require 'base64_test'
  MiniTest::Unit.autorun
end

task :default => :test

