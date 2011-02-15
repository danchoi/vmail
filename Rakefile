require 'rake'
require 'rake/testtask'
require 'bundler'
Bundler::GemHelper.install_tasks

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')

desc "release and build and push new website"
task :push => [:release, :web]

desc "Bumps version number up one and git commits"
task :bump do
  basefile = "lib/vmail/version.rb"
  file = File.read(basefile)
  oldver = file[/VERSION = '(\d.\d.\d)'/, 1]
  newver_i = oldver.gsub(".", '').to_i + 1
  newver = ("%.3d" % newver_i).split(//).join('.')
  puts oldver
  puts newver
  puts "Bumping version: #{oldver} => #{newver}"
  newfile = file.gsub("VERSION = '#{oldver}'", "VERSION = '#{newver}'") 
  File.open(basefile, 'w') {|f| f.write newfile}
  `git commit -am 'Bump'`
end


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

