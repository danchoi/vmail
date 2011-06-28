require 'vmail/version'
require 'vmail/options'
require 'vmail/imap_client'
require 'vmail/query'
require 'vmail/message_formatter'

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
                               tools = ['gnome-open', 'kfmclient-exec', 'konqueror']
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

    opts = Vmail::Options.new(ARGV)
    opts.config
    config = opts.config

    contacts_file = opts.contacts_file

    logfile = (vim == 'mvim') ? STDERR : 'vmail.log'
    config.merge! 'logfile' => logfile

    puts "Starting vmail imap client for #{config['username']}"

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
    vim_command = "DRB_URI=#{drb_uri} VMAIL_CONTACTS_FILE=#{contacts_file} VMAIL_MAILBOX=#{String.shellescape(mailbox)} VMAIL_QUERY=\"#{query_string}\" #{vim} -S #{vimscript} #{buffer_file}"
    STDERR.puts vim_command
    STDERR.puts "Using buffer file: #{buffer_file}"
    File.open(buffer_file, "w") do |file|
      file.puts "\n\nVmail #{Vmail::VERSION}\n\n"
      file.puts "Please wait while I fetch your messages.\n\n\n"
    end

    system(vim_command)

    if vim == 'mvim'
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

  # non-interactive mode
  def noninteractive_list_messages
    check_lynx
    opts = Vmail::Options.new(ARGV)
    opts.config
    config = opts.config.merge 'logfile' => 'vmail.log'
    mailbox, query = parse_query
    query_string = Vmail::Query.args2string query
    imap_client  = Vmail::ImapClient.new config
    imap_client.with_open do |vmail| 
      vmail.select_mailbox mailbox
      vmail.search query_string
    end 
  end

  # batch processing mode
  def batch_run
    check_lynx
    opts = Vmail::Options.new(ARGV)
    opts.config
    config = opts.config.merge 'logfile' => 'vmail.log'
    # no search query args, but command args
    imap_client  = Vmail::ImapClient.new config
    lines = STDIN.readlines# .reverse
    mailbox = lines.shift.chomp
    puts "mailbox: #{mailbox}"
    uid_set = lines.map do |line| 
      line[/(\d+)\s*$/,1].to_i
    end
    commands = {
      'rm' => ["flag", "+FLAGS", "Deleted"],
      'spam' => ["flag", "+FLAGS", "spam"],
      'mv' => ["move_to"],
      'cp' => ["copy_to"],
      'print' => ["append_to_file"]
    }
    args = commands[ARGV.first]
    if args.nil?
      abort "Command '#{args.inspect}' not recognized"
    end
    command = args.shift
    imap_client.with_open do |vmail| 
      puts "Selecting mailbox: #{mailbox}"
      vmail.select_mailbox mailbox
      uid_set.each_slice(5) do |uid_set|
        params = [uid_set.join(',')] + args + ARGV[1..-1]
        puts "Executing: #{command} #{params.join(' ')}"
        vmail.send command, *params
      end
    end
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
