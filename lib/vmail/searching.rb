module Vmail
  module Searching
    # The main function called by the client to retrieve messages
    def search(query)
      query = Vmail::Query.parse(query)
      @limit = query.shift.to_i
      # a limit of zero is effectively no limit
      if @limit == 0
        @limit = @num_messages
      end
      if query.size == 1 && query[0].downcase == 'all'
        # form a sequence range
        query.unshift [[@num_messages - @limit + 1 , 1].max, @num_messages].join(':')
        @all_search = true
      else # this is a special query search
        # set the target range to the whole set
        query.unshift "1:#@num_messages"
        @all_search = false
      end
      @query = query.map {|x| x.to_s.downcase}
      query_string = Vmail::Query.args2string(@query)
      log "Search query: #{@query} > #{query_string.inspect}"
      log "- @all_search #{@all_search}"
      @query = query
      @ids = reconnect_if_necessary(180) do # increase timeout to 3 minutes
        @imap.search(query_string)
      end
      # save ids in @ids, because filtered search relies on it
      fetch_ids = if @all_search
                    @ids
                  else #filtered search
                    @start_index = [@ids.length - @limit, 0].max
                    @ids[@start_index..-1]
                  end
      self.max_seqno = @ids[-1]
      log "- search query got #{@ids.size} results; max seqno: #{self.max_seqno}" 
      clear_cached_message

      uids = fetch_and_cache_headers(fetch_ids)
      log "UIDS: #{uids}"
      res = fetch_row_text uids

      if STDOUT.tty?
        with_more_message_line(res, fetch_ids[0])
      else
        # non interactive mode
        puts [@mailbox, res].join("\n")
      end
    rescue
      log "ERROR:\n#{$!.inspect}\n#{$!.backtrace.join("\n")}"
    end  
  end
end

