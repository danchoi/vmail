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
      # set the target range to the whole set
      query.unshift "1:#@num_messages"
      
      @query = query.map {|x| x.to_s.downcase}
      query_string = Vmail::Query.args2string(@query)
      log "Search query: #{@query} > #{query_string.inspect}"
      @query = query
      @ids = reconnect_if_necessary(180) do # increase timeout to 3 minutes
        @imap.search(query_string)
      end
      @start_index = [@ids.length - @limit, 0].max
      fetch_ids = @ids[@start_index..-1]
      max_seqno = @ids[-1]
      log "- search query got #{@ids.size} results; max seqno: #{self.max_seqno}" 
      clear_cached_message

      message_ids = fetch_and_cache_headers(fetch_ids)
      log "message_ids: #{message_ids}"
      res = get_message_headers message_ids

      if STDOUT.tty?
        with_more_message_line(res)
      else
        # non interactive mode
        puts [@mailbox, res].join("\n")
      end
    rescue
      log "ERROR:\n#{$!.inspect}\n#{$!.backtrace.join("\n")}"
    end  
  end
end

