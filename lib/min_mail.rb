
module MinMail
  VERSION = '0.0.1'

  def self.start

    puts "Starting min_mail #{MinMail::VERSION}"
    puts "Setting VMAIL_BROWSER to '#{ENV['VMAIL_BROWSER']}'"
    check_lynx

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
