require 'vmail/version'
require 'vmail/options'
require 'vmail/imap_client'

module Vmail
  extend self

  def start
    puts "starting vmail #{Vmail::VERSION}"

    vim = ENV['VMAIL_VIM'] || 'vim'

    ENV['VMAIL_BROWSER'] ||= 'open'

    # check for lynx
    if `which lynx` == ''
      puts "You need to install lynx on your system in order to see html-only messages"
      sleep 3
    end
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

    # TODO this is useless if we're using mvim
    server.window_width = `stty size`.strip.split(' ')[1]

    mailbox = if ARGV[0] =~ /^\d+/ 
                "INBOX"
              else 
                ARGV.shift || 'INBOX' 
              end

    server.select_mailbox mailbox

    query = ARGV.empty? ? [100, 'ALL'] : ARGV
    if query.size == 1 && query[0] =~ /^\d/
      query << "ALL"
    end
    puts "mailbox: #{mailbox}"
    puts "query: #{query.inspect}"
    
    buffer_file = "vmailbuffer"
    puts "using buffer file: #{buffer_file}"
    File.open(buffer_file, "w") do |file|
      file.puts "fetching messages. please wait..."  
    end

    # invoke vim
    vimscript = File.expand_path("../vmail.vim", __FILE__)
    vim_command = "DRB_URI=#{drb_uri} VMAIL_CONTACTS_FILE=#{contacts_file} VMAIL_MAILBOX=#{String.shellescape(mailbox)} VMAIL_QUERY=#{String.shellescape(query.join(' '))} #{vim} -S #{vimscript} #{buffer_file}"
    puts vim_command
    system(vim_command)

    if vim == 'mvim'
      DRb.thread.join
    end

    File.delete(buffer_file)

    puts "closing imap connection"  
    begin
      Timeout::timeout(5) do 
        $gmail.close
      end
    rescue Timeout::Error
      puts "close connection attempt timed out"
    end
    puts "bye"
    exit
  end
end

