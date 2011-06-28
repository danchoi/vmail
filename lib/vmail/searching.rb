module Vmail
  module Searching
    # The main function called by the client to retrieve messages
    def search(query)
      log "Query raw: #{query.inspect}"
      @query = Vmail::Query.parse(query) 
      log "Query parsed: #{@query.inspect}"
      # customizable @limit is Deprecated
      @limit = 100

      query_string = Vmail::Query.args2string(@query)
      log "Query: #{query_string.inspect}"

      @ids = reconnect_if_necessary(180) do # increase timeout to 3 minutes
        @imap.search(query_string)
      end
      if search_query?
        #@num_messages = @all_ids.size
        @start_index = [@ids.size - @limit, 0].max + 1
      else
        # set the target range to the whole set, unless it is too big
        @start_index = [@num_messages - @limit, 0].max + 1
        @query.unshift "#{@start_index}:#@num_messages"
      end
      if @ids.empty?
        return "No messages"
      end

      max_seqno = @ids[-1] # this is a instance var
      log "- Query got #{@ids.size} results; max seqno: #{self.max_seqno}" 
      clear_cached_message

      select_ids = search_query? ? @ids[-@limit,@limit] : @ids
      message_ids = fetch_and_cache_headers select_ids
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

    def search_query?
      @query != ['all']
    end
  end
end

