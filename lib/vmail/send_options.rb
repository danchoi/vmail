require 'vmail/options'

module Vmail
  class SendOptions < Vmail::Options

    def parse(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage:  vmailsend"
        opts.separator ""
        opts.separator "Specific options:"
        opts.on("-c", "--config path", String, "Path to config file") do |config_file|
          @config_file = config_file
        end
        opts.on("-v", "--version", "Show version (identical to vmail version)") do
          require 'vmail/version'
          puts "vmail #{Vmail::VERSION}\nCopyright 2010 Daniel Choi under the MIT license"
          exit
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

          @config = YAML::load(File.read(@config_file))
          if @config['password'].nil?
            @config['password'] = ask("Enter gmail password (won't be visible & won't be persisted):") {|q| q.echo = false}
          end

        rescue OptionParser::ParseError => e
          STDERR.puts e.message, "\n", opts
        end

      end
    end
  end

end

