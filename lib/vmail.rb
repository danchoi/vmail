require 'vmail/version'
require 'vmail/options'
require 'vmail/imap_client'
require 'vmail/message_formatter'
require 'vmail/reply_template'

module Vmail
  extend self

  def start
    ENV['VMAIL_BROWSER'] ||= 'open'

    vim = ENV['VMAIL_VIM'] || 'vim'
    vmail_home = ENV['VMAIL_HOME'] || File.join(ENV['HOME'], '.vmail')
    buffer_file = File.expand_path(File.join(vmail_home, "vmailbuffer"))

    # Create VMAIL_HOME if it doesn't exist.
    Dir.mkdir(vmail_home, 0700) unless File.exists?(vmail_home)

    # check for lynx
    if `which lynx` == ''
      STDERR.puts "You need to install lynx on your system in order to see html-only messages."
      sleep 3
    end

    opts   = Vmail::Options.new(ARGV)
    config = opts.config

    contacts_file = opts.contacts_file

    logfile = (vim == 'mvim') ? STDERR : "#{vmail_home}/vmail.log"
    config.merge! 'logfile' => logfile

    puts "starting vmail #{Vmail::VERSION}"
    puts "starting vmail imap client for #{config['username']}"

    drb_uri = begin
                Vmail::ImapClient.daemon config
              rescue
                puts "Failure:", $!
                exit(1)
              end

    server = DRbObject.new_with_uri drb_uri

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

    # invoke vim
    vimscript = File.expand_path("../vmail.vim", __FILE__)
    vim_command = "DRB_URI=#{drb_uri} VMAIL_HOME=#{vmail_home} VMAIL_CONTACTS_FILE=#{contacts_file} VMAIL_MAILBOX=#{String.shellescape(mailbox)} VMAIL_QUERY=#{String.shellescape(query.join(' '))} #{vim} -S #{vimscript} #{buffer_file}"
    puts vim_command

    puts "using buffer file: #{buffer_file}"
    File.open(buffer_file, "w") do |file|
      file.puts "vmail starting with values:"
      file.puts "- vmail home: #{vmail_home}"
      file.puts "- drb uri: #{drb_uri}"
      file.puts "- mailbox: #{mailbox}"
      file.puts "- query: #{query.join(' ')}"
      file.puts
      file.puts "Fetching messages. Please wait..."
    end

    system(vim_command)

    if vim == 'mvim'
      DRb.thread.join
    end

    File.delete(buffer_file)

    puts "closing imap connection"
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
end
