require 'optparse'
require 'highline/import'

module Vmail
  class Options
    attr_accessor :config
    def initialize(argv)
      config_file_locations = ['.vmailrc', "#{ENV['HOME']}/.vmailrc"]
      @config_file = config_file_locations.detect do |path|
        File.exists?(File.expand_path(path))
      end
      @config = {}
      parse argv
      @config = YAML::load(File.read(@config_file))
      if @config['password'].nil?
        @config['password'] = ask("Enter gmail password (won't be visible & won't be persisted):") {|q| q.echo = false}
      end
    end

    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage:  vmail [ options ] [ limit ] [ imap search query ]\n\n" + 
          CONFIG_FILE_INSTRUCTIONS
        opts.on("-c", "--config path", String, "Path to config file") do |config_file|
          @config_file = config_file
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        begin
          opts.parse!(argv)
          if @config_file && File.exists?(@config_file)
            puts "Using config file #{@config_file}"
          else
            puts <<EOF

Missing config file! 

#{CONFIG_FILE_INSTRUCTIONS}
EOF
            exit(1)
          end
        rescue OptionParser::ParseError => e
          STDERR.puts e.message, "\n", opts
        end
      end
    end
  end

  CONFIG_FILE_INSTRUCTIONS = <<EOF
To run vmail, you need to create a yaml file called .vmailrc and save it
either in the current directory (the directory from which you launch
vmail) or in your home directory. If you want to name this file
something else or put it in an non-standard location, use the -c option.

This file should look like this, except using your settings:

username: dhchoi@gmail.com
password: password
name: Daniel Choi
signature: |
  --
  Sent via vmail. https://github.com/danchoi/vmail

This file should be formatted according to the rules of YAML.
http://www.yaml.org/spec/1.2/spec.html

You can omit the password key-value pair if you'd rather not have the password
on disk. In that case, you'll prompted for the password each time you
start vmail.


EOF
end
