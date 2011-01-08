require 'vmail/version'
require 'vmail/options'
require 'vmail/imap_client'
require 'vmail/query'
require 'vmail/message_formatter'
require 'vmail/reply_template'

module Vmail
  extend self

  def start
    puts "starting vmail #{Vmail::VERSION}"

    vim = ENV['VMAIL_VIM'] || 'vim'
    ENV['VMAIL_BROWSER'] ||= 'open'

    check_lynx

    opts = Vmail::Options.new(ARGV)
    opts.config
    config = opts.config

    contacts_file = opts.contacts_file

    logfile = (vim == 'mvim') ? STDERR : 'vmail.log'
    config.merge! 'logfile' => logfile

    puts "starting vmail imap client for #{config['username']}"

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

    STDERR.puts "mailbox: #{mailbox}"
    STDERR.puts "query: #{query.inspect} => #{query_string}"
    
    buffer_file = "vmailbuffer"
    # invoke vim
    vimscript = File.expand_path("../vmail.vim", __FILE__)
    vim_command = "DRB_URI=#{drb_uri} VMAIL_CONTACTS_FILE=#{contacts_file} VMAIL_MAILBOX=#{String.shellescape(mailbox)} VMAIL_QUERY=#{String.shellescape(query_string)} #{vim} -S #{vimscript} #{buffer_file}"
    STDERR.puts vim_command

    STDERR.puts "using buffer file: #{buffer_file}"
    File.open(buffer_file, "w") do |file|
      file.puts "vmail starting with values:"
      file.puts "- drb uri: #{drb_uri}"
      file.puts "- mailbox: #{mailbox}"
      file.puts "- query: #{query_string}"
      file.puts
      file.puts "fetching messages. please wait..."  
    end

    system(vim_command)

    if vim == 'mvim'
      DRb.thread.join
    end

    File.delete(buffer_file)

    STDERR.puts "closing imap connection"  
    begin
      Timeout::timeout(10) do 
        $gmail.close
      end
    rescue Timeout::Error
      puts "close connection attempt timed out"
    end
    puts "bye"
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
      'delete' => ["flag", "+FLAGS", "Deleted"]
    }
    args = commands[ARGV.first]
    command = args.shift
    imap_client.with_open do |vmail| 
      puts "selecting mailbox: #{mailbox}"
      vmail.select_mailbox mailbox
      uid_set.each do |uid|
        params = [uid.to_s] + args
        puts "executing: #{command} #{params.join(' ')}"
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
    mailbox = if ARGV[0] =~ /^\d+/ 
                "INBOX"
              else 
                ARGV.shift || 'INBOX' 
              end
    query = Vmail::Query.parse(ARGV)
    [mailbox, query]
  end

end

