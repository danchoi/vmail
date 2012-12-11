require 'optparse'
require 'highline/import'

module Vmail
  class Options
    DEFAULT_VMAIL_HOME        = ENV['VMAIL_HOME'] || File.join(ENV['HOME'], '.vmail')
    DEFAULT_CONFIG_FILE       = File.join(DEFAULT_VMAIL_HOME, 'vmailrc')
    DEFAULT_CONTACTS_FILENAME = File.join(DEFAULT_VMAIL_HOME, 'vmail-contacts.txt')

    # Used with the '--get-contacts' option.
    DEFAULT_MAX_MESSAGES = 500

    attr_accessor :config
    attr_accessor :contacts_file

    def initialize(argv)
      config_file_locations = ['.vmailrc', DEFAULT_CONFIG_FILE, "#{ENV['HOME']}/.vmailrc"]
      @config_file = config_file_locations.detect do |path|
        File.exists?(File.expand_path(path))
      end
      @contacts_file = ['vmail-contacts.txt', DEFAULT_CONTACTS_FILENAME].detect  do |path|
        File.exists?(File.expand_path(path))
      end
      @config = {}
      parse argv
    end

    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage:  vmail [ options ] [ limit ] [ imap search query ]" 
        opts.separator ""
        opts.separator "Options:"
        opts.on("-c", "--config path", String, "Path to config file") do |config_file|
          @config_file = config_file
        end
        opts.on("-t", "--contacts path", String, "Path to contacts file") do |file|
          @contacts_file = file
        end
        opts.on("-g", "--get-contacts [count]", Integer, "Generate contacts file. 'count' is the number of emails to scan for contacts (default: #{DEFAULT_MAX_MESSAGES}).") do |count|
          @get_contacts = true
          @max_messages_to_scan = count || DEFAULT_MAX_MESSAGES
        end
        opts.on("-v", "--version", "Show version") do
          require 'vmail/version'
          puts "vmail #{Vmail::VERSION}\nCopyright 2010 Daniel Choi under the MIT license"
          exit
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        begin
          opts.parse!(argv)
          if @config_file && File.exists?(@config_file)
            STDERR.puts "Using config file: #{@config_file}"
          else
            STDERR.puts <<EOF

Missing config file! 

#{INSTRUCTIONS}
EOF
            exit(1)
          end

          if STDOUT.tty?
            if @contacts_file.nil?
              STDERR.puts "No contacts file found for auto-completion. See help for how to generate it."
              sleep 0.5
            else
              STDERR.puts "Using contacts file: #{@contacts_file}"
            end
          end

          @config = YAML::load(File.read(@config_file))
          if @config['password'].nil?
            @config['password'] = ask("Enter gmail password (won't be visible & won't be persisted):") {|q| q.echo = false}
          end

          if @get_contacts
            require 'vmail/contacts_extractor'
            extractor = ContactsExtractor.new(@config['username'], @config['password'])
            # Use the default contacts file if none was specified.
            @contacts_file ||= DEFAULT_CONTACTS_FILENAME
            File.open(@contacts_file, 'w') do |file|
              extractor.extract(@max_messages_to_scan) do |address| 
                STDERR.print '.'
                file.puts(address.strip)
                STDERR.flush 
              end
            end
            STDERR.print "\n"
            puts "Saved file to #{@contacts_file}"
            puts "Sorting address..."
            cmd = "sort #{@contacts_file} | uniq > vmail-tmp.txt"
            cmd2 = "mv vmail-tmp.txt #{@contacts_file}"
            `#{cmd}`
            `#{cmd2}`
            puts "Done"
            exit
          end

        rescue OptionParser::ParseError => e
          STDERR.puts e.message, "\n", opts
        end

      end
    end
  end

  INSTRUCTIONS = <<-EOF
Missing config file!

Visit http://danielchoi.com/software/vmail.html for detailed instructions.

To get started quickly, create a ~/.vmail/vmailrc file which looks like this:

username: USERNAME@gmail.com
password: PASSWORD
name: YOUR NAME
signature: |
  --
  John Doe
  john.doe@gmail.com
EOF
end
