require 'vmail/imap_client'

module Vmail
  extend self

  def start
    vim = ENV['VMAIL_VIM'] || 'vim'

    config = YAML::load(File.read(File.expand_path("~/gmail.yml")))
    logfile = (vim == 'mvim') ? STDERR : 'vmail.log'
    config.merge! 'logfile' => logfile

    puts "starting vmail imap client with config #{config}"

    drb_uri = Vmail::ImapClient.daemon config

    server = DRbObject.new_with_uri drb_uri

    # TODO this is useless if we're using mvim
    server.window_width = `stty size`.strip.split(' ')[1]

    server.select_mailbox ARGV.shift || 'INBOX'

    query = ARGV.empty? ? [100, 'ALL'] : nil
    
    buffer_file = "vmail-buffer.txt"
    puts "using buffer file: #{buffer_file}"
    File.open(buffer_file, "w") do |file|
      file.puts server.search(*query)
    end

    # invoke vim
    # TODO
    #  - mvim; move viewer.vim to new file

    vimscript = File.expand_path("../vmail.vim", __FILE__)
    vim_command = "DRB_URI='#{drb_uri}' #{vim} -S #{vimscript} #{buffer_file}"
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

