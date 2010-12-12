require 'vmail/imap_client'

module Vmail
  extend self

  def start
    config = YAML::load(File.read(File.expand_path("~/gmail.yml")))
    config.merge! 'logfile' => "vmail.log"

    puts "starting vmail imap client with config #{config}"

    drb_uri = Vmail::ImapClient.daemon config

    server = DRbObject.new_with_uri drb_uri
    server.window_width = `stty size`.strip.split(' ')[1]
    server.select_mailbox ARGV.shift || 'INBOX'

    query = ARGV.empty? ? [100, 'ALL'] : nil

    buffer_file = "vmail-buffer.txt"
    File.open(buffer_file, "w") do |file|
      file.puts server.search(*query)
    end

    # invoke vim
    # TODO
    #  - mvim; move viewer.vim to new file

    vimscript = "viewer.vim"
    system("DRB_URI='#{drb_uri}' vim -S #{vimscript} #{buffer_file}")

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

