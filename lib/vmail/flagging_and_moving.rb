module Vmail
  module FlaggingAndMoving

    def convert_to_message_ids(message_ids)
      message_ids.split(',').map {|message_id|
        labeling = Labeling[message_id: message_id, label_id: @label.label_id]
        labeling.uid
      }
    end

    # uid_set is a string comming from the vim client
    # action is -FLAGS or +FLAGS
    def flag(message_ids, action, flg)
      uid_set = convert_to_message_ids(message_ids)
      log "Flag #{uid_set} #{flg} #{action}"
      if flg == 'Deleted'
        log "Deleting uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        # for delete, do in a separate thread because deletions are slow
        spawn_thread_if_tty do
          unless @mailbox == mailbox_aliases['trash']
            log "imap.uid_copy #{uid_set.inspect} to #{mailbox_aliases['trash']}"
            log @imap.uid_copy(uid_set, mailbox_aliases['trash'])
          end
          log "imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
          reload_mailbox
          clear_cached_message
        end
      elsif flg == 'spam' || flg == mailbox_aliases['spam']
        log "Marking as spam uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        spawn_thread_if_tty do
          log "imap.uid_copy #{uid_set.inspect} to #{mailbox_aliases['spam']}"
          log @imap.uid_copy(uid_set, mailbox_aliases['spam'])
          log "imap.uid_store #{uid_set.inspect} #{action} [:Deleted]"
          log @imap.uid_store(uid_set, action, [:Deleted])
          reload_mailbox
          clear_cached_message
        end
      else
        log "Flagging uid_set: #{uid_set.inspect}"
        spawn_thread_if_tty do
          log "imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
        end
      end
    rescue
      log $!
    end

    def move_to(message_ids, mailbox)
      uid_set = convert_to_message_ids(message_ids)
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
    rescue
      log $!
    end

    def copy_to(message_ids, mailbox)
      uid_set = convert_to_message_ids(message_ids)
      if mailbox_aliases[mailbox]
        mailbox = mailbox_aliases[mailbox]
      end
      create_if_necessary mailbox
      log "Copying #{uid_set.inspect} to #{mailbox}"
      spawn_thread_if_tty do
        log @imap.uid_copy(uid_set, mailbox)
        log "Copied uid_set #{uid_set.inspect} to #{mailbox}"
      end
    rescue
      log $!
    end
  end

end
