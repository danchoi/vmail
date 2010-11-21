class Gmail

  def initialize(username, password)
    @username, @password = username, password
  end

  def open
    raise "block missing" unless block_given?
    @imap = Net::IMAP.new('imap.gmail.com', 993, true, nil, false)
    @imap.login(@username, @password)
    yield @imap
  rescue Exception => ex
    raise
  ensure
    if @imap
      @imap.close rescue Net::IMAP::BadResponseError
      @imap.disconnect
    end
  end

  def mailboxes
    open do |imap|
      (imap.list("[Gmail]/", "%") + imap.list("", "%").sort_by(&:name) )
    end
  end

  def fetch(opts)
    num_messages = opts[:num_messages] || 10
    mailbox_label = opts[:mailbox] || 'inbox'
    Vim::message "Mailbox: #{mailbox_label}; Fetching messages: #{opts.inspect}"
    @mailbox = Mailbox.find_or_create_by_label(mailbox_label)
    query = opts[:query] || ["ALL"]

    #puts "running check, using mailbox #{mailbox_label}"
    open do |imap|
      imap.select(mailbox_label)
      uids = imap.uid_search(query)[-num_messages..-1] || []
      uids.each do |message_id|

        message = Message.find_by_uid(message_id.to_s)
        if message

        else
          email = imap.uid_fetch(message_id, "RFC822")[0].attr["RFC822"]
          mail = Mail.new(email)
          from = mail.from[0]
          message = Message.create! :uid => message_id.to_s,
            :sender => mail[:from],
            :subject => mail[:subject],
            :date => mail.date,
            :eml => mail.to_s

          message.cache_text_body 
          #puts "saving [#{mail.subject}]"
        end
        if ! @mailbox.messages.find_by_uid(message_id)
          @mailbox.messages << message
        end
      end
    end
  end

end


