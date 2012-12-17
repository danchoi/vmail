require 'vmail/version'
require 'vmail/options'
require 'vmail/query'
require 'vmail/message_formatter'

require 'iconv'

module Vmail
  extend self

  def start
    puts "Starting vmail #{Vmail::VERSION}"
    if  "1.9.0" > RUBY_VERSION
      puts "This version of vmail requires Ruby version 1.9.0 or higher (1.9.2 is recommended)"
      exit
    end

    vim = ENV['VMAIL_VIM'] || 'vim'
    ENV['VMAIL_BROWSER'] ||= if RUBY_PLATFORM.downcase.include?('linux') 
                               tools = ['gnome-open', 'kfmclient-exec', 'xdg-open', 'konqueror']
                               tool = tools.detect { |tool|
                                 `which #{tool}`.size > 0
                               }
                               if tool.nil?
                                 puts "Can't find a VMAIL_BROWSER tool on your system. Please report this issue."
                               else
                                 tool
                               end
                             else
                               'open'
                             end

    puts "Setting VMAIL_BROWSER to '#{ENV['VMAIL_BROWSER']}'"
    check_lynx

    working_dir = ENV['VMAIL_HOME'] || "#{ENV['HOME']}/.vmail/default"
    `mkdir -p #{working_dir}`
    # legacy migration: move files into VMAIL_HOME
    if Dir.pwd != working_dir
      ['.vmailrc', 'vmail.log', 'vmail.db', 'vmail-contacts.txt', 'compose_message.txt', 'attachments'].each do |x|
        if File.size?(x)
          c = "mv #{x} #{working_dir}"
          puts c
          %x{#{c}}
        end
      end
    end
    puts "Changing working directory to #{working_dir}"
    Dir.chdir(working_dir)
    opts = Vmail::Options.new(ARGV)
    opts.config
    config = opts.config

    contacts_file = opts.contacts_file

    logfile = (vim == 'mvim' || vim == 'gvim') ? STDERR : 'vmail.log'
    config.merge! 'logfile' => logfile

    puts "Starting vmail imap client for #{config['username']}"

    # inbox poller
    if config['polling'] == false
      puts "INBOX polling disabled."
    else
      require 'vmail/inbox_poller'
      inbox_poller = Vmail::InboxPoller.start config
      Thread.new do
        inbox_poller.start_polling
      end
    end

    puts "WORKING DIR: #{Dir.pwd}"

    # require after the working dir is set
    require 'vmail/imap_client'

    drb_uri = begin 
                Vmail::ImapClient.daemon config
              rescue 
                puts "Failure:", $!
                exit(1)
              end

    server = DRbObject.new_with_uri drb_uri

    mailbox, query = parse_query
    query_string = Vmail::Query.args2string query
    server.select_mailbox mailbox

    STDERR.puts "Mailbox: #{mailbox}"
    STDERR.puts "Query: #{query.inspect}" 
    STDERR.puts "Query String: #{String.shellescape(query_string)}"
    
    buffer_file = "vmailbuffer"
    # invoke vim
    vimscript = File.expand_path("../vmail.vim", __FILE__)
    vimopts = config['vim_opts']
    vim_command = "DRB_URI=#{drb_uri} VMAIL_CONTACTS_FILE=#{contacts_file} VMAIL_MAILBOX=#{String.shellescape(mailbox)} VMAIL_QUERY=\"#{query_string}\" #{vim} -S #{vimscript} -c '#{vimopts}' #{buffer_file}"
    STDERR.puts vim_command
    STDERR.puts "Using buffer file: #{buffer_file}"
    File.open(buffer_file, "w") do |file|
      file.puts "\n\nVmail #{Vmail::VERSION}\n\n"
      file.puts "Please wait while I fetch your messages.\n\n\n"
    end

    system(vim_command)

    if vim == 'mvim' || vim == 'gvim'
      DRb.thread.join
    end

    File.delete(buffer_file)

    STDERR.puts "Closing imap connection"  
    begin
      Timeout::timeout(10) do 
        $gmail.close
      end
    rescue Timeout::Error
      puts "Close connection attempt timed out"
    end
    puts "Bye"
    exit
  end

  private

  def check_lynx
    # TODO check for elinks, or firefox (how do we parse VMAIL_HTML_PART_REDAER to determine?)
    if `which lynx` == ''
      STDERR.puts "You need to install lynx on your system in order to see html-only messages"
      sleep 3
    end
  end

  def parse_query
    if ARGV[0] =~ /^\d+/ 
      ARGV.shift
    end
    mailbox = ARGV.shift || 'INBOX' 
    query = Vmail::Query.parse(ARGV)
    [mailbox, query]
  end
end

if __FILE__ == $0
  Vmail.start
end
