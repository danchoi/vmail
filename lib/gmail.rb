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
      imap.list("[Gmail]/", "%") + imap.list("", "%")
    end
  end

  def fetch(opts)
    num_messages = opts[:num_messages] || 10
    mailbox_label = opts[:mailbox] || 'inbox'
    query = opts[:query] || ["ALL"]
    open do |imap|
      imap.select(mailbox_label)
      all_uids = imap.uid_search(query)
      puts "#{all_uids.size} UIDS TOTAL"
      uids = all_uids[-([num_messages, all_uids.size].min)..-1] || []
      puts "imap process uids #{uids.inspect}"
      yield imap, uids
    end
  end

  # generic mailbox operations
  def mailbox(label)
    open do |imap|
      imap.select(label)
      yield imap
    end
  end


end


