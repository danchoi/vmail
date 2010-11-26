# configure activerecord to use mysql
require 'active_record'
require 'logger'
require 'yaml'
require 'net/imap'
require 'mail'
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')

config_file = File.join(File.dirname(__FILE__), 'database.yml')
config = YAML::load(File.read(config_file))['development']
ActiveRecord::Base.establish_connection config

gmail_config_file = File.join(File.dirname(__FILE__), 'gmail.yml')
gmail_config = YAML::load(File.read(gmail_config_file))
require 'gmail'
$gmail = Gmail.new gmail_config['login'], gmail_config['password']

