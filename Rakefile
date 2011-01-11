require 'rake'
require 'rake/testtask'
require 'bundler'
Bundler::GemHelper.install_tasks

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')

desc "build and push website"
task :web do
  require 'vmail/version'
  version = Vmail::VERSION
  Dir.chdir("website") do
    puts "updating website"
    puts `./run.sh #{version}`
  end
end

desc "build website locally"
task :weblocal do
  require 'vmail/version'
  version = Vmail::VERSION
  Dir.chdir("website") do
    `ruby gen.rb #{version} > vmail.html`
    `open vmail.html`
  end
end

desc "git push and rake release bumped version"
task :bumped do
  puts `git push && rake release`
  Rake::Task["web"].execute
end

desc "Run tests"
task :test do 
  $:.unshift File.expand_path("test")
  require 'test_helper'
  Dir.chdir("test") do 
    Dir['*_test.rb'].each do |x|
      puts "requiring #{x}"
      require x
    end
  end

  MiniTest::Unit.autorun
end

task :default => :test

