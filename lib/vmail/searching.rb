module Vmail
  module Searching
    # The main function called by the client to retrieve messages
    def search(query)
      log "Search query raw: #{query.inspect}"
      @query = Vmail::Query.parse(query) 
      log "Search query parsed: #{@query.inspect}"
      # customizable @limit is Deprecated
      @limit = 100
      # set the target range to the whole set, unless it is too big
      @start_index = [@num_messages - @limit, 0].max + 1
      @query.unshift "#{@start_index}:#@num_messages"
      query_string = Vmail::Query.args2string(@query)
      log "Search query: #{query_string.inspect}"
      @ids = reconnect_if_necessary(180) do # increase timeout to 3 minutes
        @imap.search(query_string)
      end
      if @ids.empty?
        return "No messages"
      end
      max_seqno = @ids[-1] # this is a instance var
      log "- search query got #{@ids.size} results; max seqno: #{self.max_seqno}" 
      clear_cached_message

      message_ids = fetch_and_cache_headers @ids
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

