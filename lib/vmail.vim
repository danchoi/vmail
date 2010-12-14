let s:mailbox = $VMAIL_MAILBOX
let s:query = $VMAIL_QUERY
let s:append_file = ''

let s:drb_uri = $DRB_URI

let s:client_script = "vmail_client " . s:drb_uri . " "
let s:set_window_width_command = s:client_script . "window_width= "
let s:list_mailboxes_command = s:client_script . "list_mailboxes "
let s:show_message_command = s:client_script . "show_message "
let s:update_command = s:client_script . "update"
let s:fetch_headers_command = s:client_script . "fetch_headers "
let s:select_mailbox_command = s:client_script . "select_mailbox "
let s:search_command = s:client_script . "search "
let s:more_messages_command = s:client_script . "more_messages "
let s:flag_command = s:client_script . "flag "
let s:append_to_file_command = s:client_script . "append_to_file "
let s:move_to_command = s:client_script . "move_to "
let s:copy_to_command = s:client_script . "copy_to "
let s:new_message_template_command = s:client_script . "new_message_template "
let s:reply_template_command = s:client_script . "reply_template "
let s:forward_template_command = s:client_script . "forward_template "
let s:deliver_command = s:client_script . "deliver "
let s:save_draft_command = s:client_script . "save_draft "
let s:save_attachments_command = s:client_script . "save_attachments "
let s:open_html_command = s:client_script . "open_html_part "
let s:message_bufname = "MessageWindow"

function! VmailStatusLine()
  return "%<%f\ " . s:mailbox . " " . s:query . "%r%=%-14.(%l,%c%V%)\ %P"
endfunction

function! s:create_list_window()
  "setlocal bufhidden=delete
  "setlocal buftype=nofile
  setlocal nomodifiable
  setlocal noswapfile
  "setlocal nomodifiable
  setlocal nowrap
  setlocal nonumber
  setlocal foldcolumn=0
  setlocal nospell
  " setlocal nobuflisted
  setlocal textwidth=0
  setlocal noreadonly
  " hi CursorLine cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white 
  setlocal cursorline
  " we need the bufnr to find the window later
  let s:listbufnr = bufnr('%')
  setlocal statusline=%!VmailStatusLine()
  call s:message_list_window_mappings()
endfunction

" the message display buffer window
function! s:create_message_window() 
  exec "split " . s:message_bufname
  setlocal buftype=nofile
  " setlocal noswapfile
  " setlocal nobuflisted
  let s:message_window_bufnr = bufnr('%')
  call s:message_window_mappings()
  close
endfunction

function! s:show_message()
  let line = getline(line("."))
  if match(line, '^> Load') != -1
    setlocal modifiable
    delete
    call s:more_messages()
    return
  endif
  " remove the unread flag  [+]
  let newline = substitute(line, "\\[+\]\\s*", "", '')
  setlocal modifiable
  call setline(line('.'), newline)
  setlocal nomodifiable
  write
  " this just clears the command line and prevents the screen from
  " moving up when the next echo statement executes:
  call feedkeys(":\<cr>") 
  redraw
  let selected_uid = matchstr(line, '^\d\+')
  let s:current_uid = selected_uid
  let command = s:show_message_command . s:current_uid
  echom "Loading message. Please wait..."
  redrawstatus
  let res = system(command)
  call s:focus_message_window()
  setlocal modifiable
  1,$delete
  put =res
  " critical: don't call execute 'normal \<cr>'
  " call feedkeys("<cr>") 
  1delete
  normal 1
  normal jk
  setlocal nomodifiable
  redraw
endfunction

" from message window
function! s:show_next_message()
  call s:focus_list_window()
  execute "normal j"
  execute "normal \<cr>"
endfunction

function! s:show_previous_message()
  call s:focus_list_window()
  execute "normal k" 
  if line('.') != 1
    execute "normal \<cr>"
  endif
endfunction

" from message list window
function! s:show_next_message_in_list()
  if line('.') != line('$')
    call feedkeys("j\<cr>\<cr>") 
  endif
endfunction

function! s:show_previous_message_in_list()
  if line('.') != 1
    call feedkeys("k\<cr>\<cr>") 
  endif
endfunction


" invoked from withint message window
function! s:show_raw()
  let command = s:show_message_command . s:current_uid . ' raw'
  echo command
  setlocal modifiable
  1,$delete
  let res = system(command)
  put =res
  1delete
  normal 1G
  setlocal nomodifiable
endfunction


function! s:focus_list_window()
  let winnr = bufwinnr(s:listbufnr) 
  if winnr == -1
    " create window
    split
    exec "buffer" . s:listbufnr
  else
    exec winnr . "wincmd w"
  endif
  " set up syntax highlighting
  if has("syntax")
    syn clear
    syn match BufferFlagged /^.*[*].*$/hs=s
    hi def BufferFlagged ctermfg=red ctermbg=black
  endif
  " vertically center the cursor line
  normal z.
  call feedkeys("\<c-l>") " prevents screen artifacts when user presses return too fast
endfunction

function! s:focus_message_window()
  let winnr = bufwinnr(s:message_window_bufnr)
  if winnr == -1
    " create window
    exec "botright split " . s:message_bufname
  else
    exec winnr . "wincmd w"
  endif
endfunction

" gets new messages since last update
function! s:update()
  let command = s:update_command
  echo "checking for new messages. please wait..."
  let res = system(command)
  if match(res, '^\d\+') != -1
    setlocal modifiable
    let line = line('$')
    $put =res
    setlocal nomodifiable
    write
    let num = len(split(res, '\n', ''))
    redraw
    call cursor(line + 1, 0)
    normal z.
    redraw
    echo "you have " . num . " new message" . (num == 1 ? '' : 's') . "!" 
  else
    redraw
    echo "no new messages"
  endif
endfunction

function! s:toggle_star() range
  let lnum = a:firstline
  let n = 0
  let uids = []
  while lnum <= a:lastline
    let line =  getline(lnum)
    let message_uid = matchstr(line, '^\d\+')
    call add(uids, message_uid)
    let lnum = lnum + 1
  endwhile
  let uid_set = join(uids, ",")
  let flag_symbol = "[*]"
  " check if starred already
  let action = " +FLAGS"
  if (match(line, flag_symbol) != -1)
    let action = " -FLAGS"
  endif
  let command = s:flag_command . uid_set . action . " Flagged" 
  if len(uids) == 1
    echom "toggling flag on message " . uid_set
  else
    echom "toggling flags on messages " . join(uid_set, ",")
  endif
  " toggle [*] on lines
  let res = system(command)
  setlocal modifiable
  exec a:firstline . "," . a:lastline . "delete"
  exec (a:firstline - 1). "put =res"
  setlocal nomodifiable
  write
  " if more than 2 lines change, vim forces us to look at a message.
  " dismiss it.
  if len(split(res, "\n")) > 2
    call feedkeys("\<cr>")
  endif
endfunction

" flag can be Deleted or [Gmail]/Spam
func! s:delete_messages(flag) range
  let lnum = a:firstline
  let n = 0
  let uids = []
  while lnum <= a:lastline
    let line =  getline(lnum)
    let message_uid = matchstr(line, '^\d\+')
    call add(uids, message_uid)
    let lnum = lnum + 1
  endwhile
  let uid_set = join(uids, ",")
  let command = s:flag_command . uid_set . " +FLAGS " . a:flag
  echo command
  let res = system(command)
  setlocal modifiable
  exec a:firstline . "," . a:lastline . "delete"
  setlocal nomodifiable
  write
  " if more than 2 lines change, vim forces us to look at a message.
  " dismiss it.
  if len(uids) > 2
    call feedkeys("\<cr>")
  endif
  call s:focus_message_window()
  close
  redraw
  echo len(uids) . " message" . (len(uids) == 1 ? '' : 's') . " marked " . a:flag

endfunc

func! s:archive_messages() range
  let lnum = a:firstline
  let n = 0
  let uids = []
  while lnum <= a:lastline
    let line =  getline(lnum)
    let message_uid = matchstr(line, '^\d\+')
    call add(uids, message_uid)
    let lnum = lnum + 1
  endwhile
  let uid_set = join(uids, ",")
  let command = s:move_to_command . uid_set . ' ' . shellescape("[Gmail]/All Mail")
  echo "archiving message" . (len(uids) == 1 ? '' : 's')
  let res = system(command)
  setlocal modifiable
  exec a:firstline . "," . a:lastline . "delete"
  setlocal nomodifiable
  write
  call s:focus_message_window()
  close
  redraw
  echo len(uids) . " message" . (len(uids) == 1 ? '' : 's') . " archived"
endfunc


" --------------------------------------------------------------------------------
" append text bodies of a set of messages to a file
func! s:append_messages_to_file() range
  let lnum = a:firstline
  let n = 0
  let uids = []
  while lnum <= a:lastline
    let line =  getline(lnum)
    let message_uid = matchstr(line, '^\d\+')
    call add(uids, message_uid)
    let lnum = lnum + 1
  endwhile
  let uid_set = join(uids, ",")
  let s:append_file = input("print messages to file: ", s:append_file)
  let command = s:append_to_file_command . s:append_file . ' ' . uid_set 
  echo "appending " . len(uids) . " message" . (len(uids) == 1 ? '' : 's') . " to " s:append_file
  let res = system(command)
  echo res
  redraw
endfunc

" --------------------------------------------------------------------------------
" move to another mailbox
function! s:move_to_mailbox(copy) range
  let s:copy_to_mailbox = a:copy
  let lnum = a:firstline
  let n = 0
  let uids = []
  while lnum <= a:lastline
    let line =  getline(lnum)
    let message_uid = matchstr(line, '^\d\+')
    call add(uids, message_uid)
    let lnum = lnum + 1
  endwhile
  let s:uid_set = join(uids, ",")
  " now prompt use to select mailbox
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  topleft split MailboxSelect
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  resize 1
  let prompt = "select mailbox to " . (a:copy ? 'copy' : 'move') . " to: "
  call setline(1, prompt)
  normal $
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>complete_move_to_mailbox()<CR> 
  inoremap <silent> <buffer> <esc> <Esc>:q<cr>
  set completefunc=CompleteMoveMailbox
  " c-p clears the line
  let s:firstline = a:firstline 
  let s:lastline = a:lastline
  call feedkeys("a\<c-x>\<c-u>\<c-p>", 't')
  " save these in script scope to delete the lines when move completes
endfunction

function! s:complete_move_to_mailbox()
  let mailbox = get(split(getline(line('.')), ": "), 1)
  close
  if s:copy_to_mailbox 
    let command = s:copy_to_command . s:uid_set . ' ' . shellescape(mailbox)
  else
    let command = s:move_to_command . s:uid_set . ' ' . shellescape(mailbox)
  endif
  redraw
  echo "moving uids ". s:uid_set . " to mailbox " . mailbox 
  let res = system(command)
  setlocal modifiable
  if !s:copy_to_mailbox
    exec s:firstline . "," . s:lastline . "delete"
  end
  setlocal nomodifiable
  write
  redraw
  echo "done"
endfunction

function! CompleteMoveMailbox(findstart, base)
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  if a:findstart
    " locate the start of the word
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '\a'
      let start -= 1
    endwhile
    return start
  else
    " find months matching with "a:base"
    let res = []
    for m in s:mailboxes
      if m == s:mailbox
        continue
      endif
      if m =~ '^' . a:base
        call add(res, m)
      endif
    endfor
    return res
  endif
endfun
" --------------------------------------------------------------------------------

function! s:get_mailbox_list()
  let command = s:list_mailboxes_command
  redraw
  echo command
  let res = system(command)
  let s:mailboxes = split(res, "\n", '')
endfunction

" -------------------------------------------------------------------------------
" select mailbox

function! s:mailbox_window()
  call s:get_mailbox_list()
  topleft split MailboxSelect
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  resize 1
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>select_mailbox()<CR> 
  inoremap <silent> <buffer> <esc> <Esc>:q<cr>
  set completefunc=CompleteMailbox
  " c-p clears the line
  call setline(1, "select mailbox to switch to: ")
  normal $
  call feedkeys("a\<c-x>\<c-u>\<c-p>", 't')
endfunction

function! CompleteMailbox(findstart, base)
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  if a:findstart
    " locate the start of the word
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '\a'
      let start -= 1
    endwhile
    return start
  else
    " find mailboxes matching with "a:base"
    let res = []
    for m in s:mailboxes
      if m =~ '^' . a:base
        call add(res, m)
      endif
    endfor
    return res
  endif
endfun

function! s:select_mailbox()
  let mailbox = get(split(getline(line('.')), ": "), 1)
  close
  call s:focus_message_window()
  close
  let s:mailbox = mailbox
  let command = s:select_mailbox_command . shellescape(s:mailbox)
  call system(command)
  redraw
  " now get latest 100 messages
  call s:focus_list_window()  
  setlocal modifiable
  let command = s:search_command . "100 all"
  echo "Please wait. Loading messages..."
  let res = system(command)
  1,$delete
  put! =res
  execute "normal Gdd\<c-y>" 
  normal G
  setlocal nomodifiable
  write
  normal z.
endfunction

func! s:search_query()
  if !exists("s:query")
    let s:query = ""
  endif
  let s:query = input("search query: ", s:query)
  call s:do_search()
endfunc

function! s:do_search()
  " empty query
  if match(s:query, '^\s*$') != -1
    return
  endif
  " close message window if open
  call s:focus_message_window()
  close
  " if query doesn't start with a number, set max returned to 100
  let limit = 100
  let imap_query = s:query
  if match(s:query, '^\d') == 0
    let query_chunks = split(s:query, '\s')
    let limit = remove(query_chunks, 0)
    let imap_query = join(query_chunks, ' ')
  end
  let s:query = limit . ' ' . imap_query
  let command = s:search_command . limit . ' ' . shellescape(imap_query)
  redraw
  call s:focus_list_window()  
  setlocal modifiable
  echo "running query on " . s:mailbox . ": " . s:query . ". please wait..."
  let res = system(command)
  1,$delete
  put! =res
  execute "normal Gdd\<c-y>" 
  normal z.
  setlocal nomodifiable
  write
endfunction

function! s:more_messages()
  let line = getline(line('.'))
  let uid = matchstr(line, '^\d\+')
  let command = s:more_messages_command . uid
  echo command
  let res = system(command)
  setlocal modifiable
  let lines =  split(res, "\n")
  call append(0, lines)
  " execute "normal Gdd\<c-y>" 
  setlocal nomodifiable

endfunction

" --------------------------------------------------------------------------------  
"  compose reply, compose, forward, save draft

function! s:compose_reply(all)
  let command = s:reply_template_command . s:current_uid
  if a:all
    let command = command . ' 1'
  endif
  call s:open_compose_window(command)
  " cursor after headers
  normal }
  normal o
endfunction

function! s:compose_message()
  let command = s:new_message_template_command
  call s:open_compose_window(command)
  " position cursor after to:
  call search("^to:")
  normal $
  call feedkeys("a")
endfunction

function! s:compose_forward()
  let command = s:forward_template_command . s:current_uid
  call s:open_compose_window(command)
  call search("^to:")
  normal $
  call feedkeys("a")
endfunction

func! s:open_compose_window(command)
  redraw
  echo a:command
  let res = system(a:command)
  split compose-message
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  wincmd p 
  close!
  1,$delete
  put! =res
  call feedkeys("\<cr>")
  normal 1G
  call s:compose_window_mappings()
  set completefunc=CompleteContact
endfunc

" contacts.txt file should be generated. 
" grep works well, does partial matches
function! CompleteContact(findstart, base)
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  if a:findstart
    " locate the start of the word
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '\a'
      let start -= 1
    endwhile
    return start
  else
    " find contacts matching with "a:base"
    let matches = system("grep -i " . shellescape(a:base) . " " . $VMAIL_CONTACTS_FILE)
    return split(matches, "\n")
  endif
endfun

function! s:cancel_compose()
  call s:focus_list_window()
  wincmd p
  close!
endfunction

function! s:send_message()
  let mail = join(getline(1,'$'), "\n")
  echo "sending message"
  call system(s:deliver_command, mail)
  redraw
  echo "sent! press q to go back to message list"
endfunction

func! s:save_draft()
  let mail = join(getline(1,'$'), "\n")
  echo "saving draft"
  call system(s:save_draft_command, mail)
  redraw
  call s:focus_list_window()
  wincmd p
  close!
  echo "draft saved"
endfunc

" -------------------------------------------------------------------------------- 

" call from inside message window with <Leader>h
func! s:open_html_part()
  let command = s:open_html_command . s:current_uid 
  let outfile = system(command)
  " todo: allow user to change open in browser command?
  exec "!open " . outfile
endfunc

func! s:save_attachments()
  if !exists("s:savedir")
    let s:savedir = getcwd() . "/attachments"
  end
  let s:savedir = input("save attachments to directory: ", s:savedir)
  let command = s:save_attachments_command . s:savedir
  let res = system(command)
  echo res
endfunc
" -------------------------------------------------------------------------------- 

func! s:toggle_fullscreen()
  if winnr('$') > 1
    only
    normal z.
  else
    call feedkeys("\<cr>")
  endif
endfunc


" -------------------------------------------------------------------------------- 
" MAPPINGS

func! s:message_window_mappings()
  noremap <silent> <buffer> <cr> :call <SID>focus_list_window()<CR> 
  noremap <silent> <buffer> <Leader>r :call <SID>compose_reply(0)<CR>
  noremap <silent> <buffer> <Leader>a :call <SID>compose_reply(1)<CR>
  noremap <silent> <buffer> <Leader>R :call <SID>show_raw()<cr>
  noremap <silent> <buffer> <Leader>R :call <SID>show_raw()<cr>
  noremap <silent> <buffer> <Leader>f :call <SID>compose_forward()<CR><cr>
  " TODO improve this
  noremap <silent> <buffer> <Leader>o yE :!open '<C-R>"'<CR><CR>
  noremap <silent> <buffer> <c-j> :call <SID>show_next_message()<CR> 
  noremap <silent> <buffer> <c-k> :call <SID>show_previous_message()<CR> 
  nmap <silent> <buffer> <leader>j <c-j>
  nmap <silent> <buffer> <leader>k <c-k>
  noremap <silent> <buffer> <Leader>c :call <SID>compose_message()<CR>
  noremap <silent> <buffer> <Leader>h :call <SID>open_html_part()<CR><cr>
  nnoremap <silent> <buffer> q :close<cr>
  nnoremap <silent> <buffer> <leader>#  :call <SID>focus_list_window()<cr>:call <SID>delete_messages("Deleted")<cr>
  nnoremap <silent> <buffer> <leader>*  :call <SID>focus_list_window()<cr>:call <SID>toggle_star()<cr>
  nnoremap <silent> <buffer> <Leader>b :call <SID>focus_list_window()<cr>call <SID>move_to_mailbox(0)<CR>
  nnoremap <silent> <buffer> <Leader>B :call <SID>focus_list_window()<cr>call <SID>move_to_mailbox(1)<CR>
  nnoremap <silent> <buffer> <leader>e  :call <SID>focus_list_window()<cr>:call <SID>archive_messages()<cr>
  nnoremap <silent> <buffer> u :call <SID>focus_list_window()<cr>:call <SID>update()<CR>
  nnoremap <silent> <buffer> <Leader>m :call <SID>focus_list_window()<cr>:call <SID>mailbox_window()<CR>
  nnoremap <silent> <buffer> <Leader>A :call <SID>save_attachments()<cr>
  " go fullscreen
  nnoremap <silent> <buffer> <Space> :call <SID>toggle_fullscreen()<cr>
endfunc

func! s:message_list_window_mappings()
  noremap <silent> <buffer> <cr> :call <SID>show_message()<CR>
  noremap <silent> <buffer> q :qal!<cr>
  noremap <silent> <buffer> <leader>* :call <SID>toggle_star()<CR>
  noremap <silent> <buffer> <leader># :call <SID>delete_messages("Deleted")<CR>
  noremap <silent> <buffer> <leader>! :call <SID>delete_messages("[Gmail]/Spam")<CR>
  noremap <silent> <buffer> <leader>e :call <SID>archive_messages()<CR>
  "open a link browser (os x)
  "autocmd CursorMoved <buffer> call <SID>show_message()
  noremap <silent> <buffer> <leader>vp :call <SID>append_messages_to_file()<CR>
  noremap <silent> <buffer> u :call <SID>update()<CR>
  noremap <silent> <buffer> <Leader>s :call <SID>search_query()<CR>
  noremap <silent> <buffer> <Leader>m :call <SID>mailbox_window()<CR>
  noremap <silent> <buffer> <Leader>b :call <SID>move_to_mailbox(0)<CR>
  noremap <silent> <buffer> <Leader>B :call <SID>move_to_mailbox(1)<CR>
  noremap <silent> <buffer> <Leader>c :call <SID>compose_message()<CR>
  noremap <silent> <buffer> <Leader>r :call <SID>show_message()<cr>:call <SID>compose_reply(0)<CR>
  noremap <silent> <buffer> <Leader>a :call <SID>show_message()<cr>:call <SID>compose_reply(1)<CR>
  noremap <silent> <buffer> <c-j> :call <SID>show_next_message_in_list()<cr>
  noremap <silent> <buffer> <c-k> :call <SID>show_previous_message_in_list()<cr>
  nnoremap <silent> <buffer> <Space> :call <SID>toggle_fullscreen()<cr>
endfunc

func! s:compose_window_mappings()
  " NOTE send_message is a global mapping, so user can load a saved
  " message from a file and send it
  nnoremap <silent> <Leader>vs :call <SID>send_message()<CR>
  nnoremap <silent> <buffer> <Leader>vd :call <SID>save_draft()<CR>
  noremap <silent> <buffer> <leader>q :call <SID>cancel_compose()<cr>
  nmap <silent> <buffer> q <leader>q
endfunc

call s:create_list_window()

call s:create_message_window()

call s:focus_list_window() " to go list window

" send window width
call system(s:set_window_width_command . winwidth(1))

autocmd VimResized <buffer> call system(s:set_window_width_command . winwidth(1))

call system(s:select_mailbox_command . shellescape(s:mailbox))
call s:do_search()



