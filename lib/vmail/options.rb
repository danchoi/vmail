require 'optparse'
require 'highline/import'

module Vmail
  class Options
    DEFAULT_CONTACTS_FILENAME = "vmail-contacts.txt"
    attr_accessor :config
    attr_accessor :contacts_file
    def initialize(argv)
      config_file_locations = ['.vmailrc', "#{ENV['HOME']}/.vmailrc"]
      @config_file = config_file_locations.detect do |path|
        File.exists?(File.expand_path(path))
      end
      @contacts_file = [DEFAULT_CONTACTS_FILENAME, "#{ENV['HOME']}/#{DEFAULT_CONTACTS_FILENAME}"].detect  do |path|
        File.exists?(File.expand_path(path))
      end
      @config = {}
      parse argv
    end

    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage:  vmail [ options ] [ limit ] [ imap search query ]" 
        opts.separator ""
        opts.separator "Specific options:"
        opts.on("-c", "--config path", String, "Path to config file") do |config_file|
          @config_file = config_file
        end
        opts.on("-t", "--contacts path", String, "Path to contacts file") do |file|
          @contacts_file = file
        end
        opts.on("-g[n]", "--getcontacts[n]", Integer, "Generate contacts file. n is number of emails to scan (default 500).") do |n| 
          @get_contacts = true
          @max_messages_to_scan = n || 500
        end
        opts.on("-h", "--help", "Show this message") do
          puts opts
          exit
        end
        opts.separator ""
        opts.separator INSTRUCTIONS

        begin
          opts.parse!(argv)
          if @config_file && File.exists?(@config_file)
            puts "Using config file #{@config_file}"
          else
            puts <<EOF

Missing config file! 

#{INSTRUCTIONS}
EOF
            exit(1)
          end

          if @contacts_file.nil?
            puts "No contacts file found for auto-completion. See help for how to generate it."
            sleep 0.5
          else
            puts "Using contacts file #{@contacts_file}"
          end

          @config = YAML::load(File.read(@config_file))
          if @config['password'].nil?
            @config['password'] = ask("Enter gmail password (won't be visible & won't be persisted):") {|q| q.echo = false}
          end

          if @get_contacts
            require 'vmail/contacts_extractor'
            extractor = ContactsExtractor.new(@config['username'], @config['password'])
            File.open(DEFAULT_CONTACTS_FILENAME, 'w') do |file|
              extractor.extract(@max_messages_to_scan) do |address| 
                STDERR.print '.'
                file.puts(address.strip)
                STDERR.flush 
              end
            end
            STDERR.print "\n"
            puts "saved file to #{DEFAULT_CONTACTS_FILENAME}"
            puts "sorting address..."
            cmd = "sort #{DEFAULT_CONTACTS_FILENAME} | uniq > vmail-tmp.txt" 
            cmd2 = "mv vmail-tmp.txt #{DEFAULT_CONTACTS_FILENAME}"
            `#{cmd}`
            `#{cmd2}`
            puts "done"
            exit
          end

        rescue OptionParser::ParseError => e
          STDERR.puts e.message, "\n", opts
        end

      end
    end
  end

  INSTRUCTIONS = <<-EOF
Please visit http://danielchoi.com/software/vmail.html for instructions
on how to configure and run vmail.

  EOF
end
