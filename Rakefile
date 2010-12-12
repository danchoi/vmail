require 'rake'
require 'rake/testtask'
require 'bundler'
Bundler::GemHelper.install_tasks

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')

desc "Run tests"
task :test do 
  $:.unshift File.expand_path("test")
  require 'test_helper'
  require 'time_format_test'
  require 'message_formatter_test'
  require 'base64_test'
  MiniTest::Unit.autorun
end

task :default => :test

