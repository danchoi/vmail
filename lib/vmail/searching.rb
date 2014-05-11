module Vmail
  module Searching
    # The main function called by the client to retrieve messages
    def search(query)
      log "#search: #{query.inspect}"
      @query = Vmail::Query.parse(query)
      # customizable @limit is Deprecated
      @limit = 100

      if search_query?
        #@num_messages = @all_ids.size
        query_string = Vmail::Query.args2string(@query)
        @ids = reconnect_if_necessary(180) do # timeout of 3 minutes
          @imap.search(query_string)
        end
        @start_index = [@ids.size - @limit, 0].max
      else
        # set the target range to the whole set, unless it is too big
        @start_index = [@num_messages - @limit, 0].max
        @query.unshift "#{@start_index + 1}:#{@num_messages}"
        query_string = Vmail::Query.args2string(@query)
        log "Query: #{query_string.inspect}"
        @ids = reconnect_if_necessary(180) do # timeout of 3 minutes
          @imap.search(query_string)
        end
      end

      if @ids.empty?
        return "No messages"
      end

      self.max_seqno = @ids[-1] # this is a instance var
      log "- Query got #{@ids.size} results; max seqno: #{self.max_seqno}"
      clear_cached_message

      select_ids = (search_query? ? @ids[[-@limit, 0].max, @limit] : @ids)

      if select_ids.size > @limit
        raise "Too many messages to fetch headers for"
      end

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
      "Sorry there was an error. Please check vmail.log."
    end

    def search_query?
      x = @query[-1] != 'all'
      #log "Search query? #{x}"
      x
    end
  end
end

