require 'optparse'
module Vmail
  class Options
    attr_accessor :config
    def initialize(argv)
      config_file_locations = ['.vmailrc', '~/.vmailrc']
      @config_file = config_file_locations.detect do |path|
        File.exist?(path)
      end
      @config = {}
      parse argv
      @config = YAML::load(File.read(@config_file))
    end

    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage:  vmail [ options ] [ limit ] [ imap search query ]"
        opts.on("-c", "--config path", String, "Path to config file") do |config_file|
          @config_file = config_file
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
      end
      begin
        opts.parse!(argv)
        if File.exist?(@config_file)
          puts "Using config file #{@config_file}"
        else
          puts "Missing config file!"
          exit(1)
        end
      rescue OptionParser::ParserError => e
        STDERR.puts e.message, "\n", opts
      end
    end
  end
end
