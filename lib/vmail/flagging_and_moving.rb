module Vmail
  module FlaggingAndMoving

    # flags is an array like [:Flagged, :Seen]
    def format_flags(flags)
      # other flags like "Old" should be hidden here
      flags = flags.split(',').map {|flag| FLAGMAP[flag] || flag}
      flags.delete("Old")
      if flags.delete(:Seen).nil?
        flags << '+' # unread
      end
      flags.join('')
    end
  
    # id_set is a string comming from the vim client
    # action is -FLAGS or +FLAGS
    def flag(uid_set, action, flg)
      log "Flag #{uid_set} #{flg} #{action}"
      uid_set = uid_set.split(',').map(&:to_i)
      if flg == 'Deleted'
        log "Deleting uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        # for delete, do in a separate thread because deletions are slow
        spawn_thread_if_tty do 
          unless @mailbox == mailbox_aliases['trash']
            log "@imap.uid_copy #{uid_set.inspect} to #{mailbox_aliases['trash']}"
            log @imap.uid_copy(uid_set, mailbox_aliases['trash'])
          end
          log "@imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
          reload_mailbox
          clear_cached_message
        end
      elsif flg == 'spam' || flg == mailbox_aliases['spam'] 
        log "Marking as spam uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        spawn_thread_if_tty do 
          log "@imap.uid_copy #{uid_set.inspect} to #{mailbox_aliases['spam']}"
          log @imap.uid_copy(uid_set, mailbox_aliases['spam']) 
          log "@imap.uid_store #{uid_set.inspect} #{action} [:Deleted]"
          log @imap.uid_store(uid_set, action, [:Deleted])
          reload_mailbox
          clear_cached_message
        end
      else
        log "Flagging uid_set: #{uid_set.inspect}"
        spawn_thread_if_tty do
          log "@imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
        end
      end
    end

    def move_to(uid_set, mailbox)
      uid_set = uid_set.split(',').map(&:to_i)
      decrement_max_seqno(uid_set.size)
      log "Move #{uid_set.inspect} to #{mailbox}"
      if mailbox == 'all'
        log "Archiving messages"
      end
      if mailbox_aliases[mailbox]
        mailbox = mailbox_aliases[mailbox]
      end
      create_if_necessary mailbox
      log "Moving uid_set: #{uid_set.inspect} to #{mailbox}"
      spawn_thread_if_tty do 
        log @imap.uid_copy(uid_set, mailbox)
        log @imap.uid_store(uid_set, '+FLAGS', [:Deleted])
        reload_mailbox
        clear_cached_message
        log "Moved uid_set #{uid_set.inspect} to #{mailbox}"
      end
    end

    def copy_to(uid_set, mailbox)
      uid_set = uid_set.split(',').map(&:to_i)
      if mailbox_aliases[mailbox]
        mailbox = mailbox_aliases[mailbox]
      end
      create_if_necessary mailbox
      log "Copying #{uid_set.inspect} to #{mailbox}"
      spawn_thread_if_tty do 
        log @imap.uid_copy(uid_set, mailbox)
        log "Copied uid_set #{uid_set.inspect} to #{mailbox}"
      end
    end
end

end
