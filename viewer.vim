let s:mailbox = ''
let s:num_msgs = 0 " number of messages
let s:query = ''

let s:drb_uri = $DRB_URI

let s:client_script = "ruby lib/client.rb " . s:drb_uri . " "
let s:list_mailboxes_command = s:client_script . "list_mailboxes "
let s:lookup_command = s:client_script . "lookup "
let s:update_command = s:client_script . "update"
let s:fetch_headers_command = s:client_script . "fetch_headers "
let s:select_mailbox_command = s:client_script . "select_mailbox "
let s:search_command = s:client_script . "search "
let s:more_messages_command = s:client_script . "more_messages "
let s:flag_command = s:client_script . "flag "
let s:move_to_command = s:client_script . "move_to "
let s:message_template_command = s:client_script . "message_template "
let s:reply_template_command = s:client_script . "reply_template "
let s:deliver_command = s:client_script . "deliver "
let s:message_bufname = "MessageWindow"
let s:list_bufname = "MessageListWindow"

function! VmailStatusLine()
  return "%<%f\ " . s:mailbox . "%r%=%-14.(%l,%c%V%)\ %P"
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
endfunction

" the message display buffer window
function! s:create_message_window() 
  exec "split " . s:message_bufname
  setlocal buftype=nofile
  " setlocal noswapfile
  " setlocal nobuflisted
  let s:message_window_bufnr = bufnr('%')
  " message window bindings
  noremap <silent> <buffer> <cr> :call <SID>focus_list_window()<CR> 
  noremap <silent> <buffer> q :call <SID>focus_list_window()<CR> 
  noremap <silent> <buffer> <Leader>r :call <SID>compose_reply(0)<CR><cr>
  noremap <silent> <buffer> r :call <SID>compose_reply(0)<CR><cr>
  noremap <silent> <buffer> <Leader>a :call <SID>compose_reply(1)<CR><cr>
  noremap <silent> <buffer> a :call <SID>compose_reply(1)<CR><cr>
  noremap <silent> <buffer> <Leader>R :call <SID>show_raw()<cr>
  noremap <silent> <buffer> R :call <SID>show_raw()<cr>
  " TODO improve this
  noremap <silent> <buffer> <Leader>o yE :!open '<C-R>"'<CR><CR>
  noremap <silent> <buffer> <leader>j :call <SID>show_next_message()<CR> 
  noremap <silent> <buffer> <leader>k :call <SID>show_previous_message()<CR> 
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
  let selected_uid = matchstr(line, '^\d\+')
  let s:current_uid = selected_uid
  let command = s:lookup_command . s:current_uid
  call s:focus_message_window()
  setlocal modifiable
  1,$delete
  echo "Loading message. Please wait..."
  let res = system(command)
  put =res
  " critical: don't call execute 'normal \<cr>'
  " call feedkeys("<cr>") 
  1delete
  normal 1
  normal jk
  wincmd p
  close
  setlocal nomodifiable
  redraw
endfunction

function! s:show_next_message()
  call s:focus_list_window()
  execute "normal j"
  if line('$') != line('.')
    execute "normal \<cr>"
  endif
endfunction

function! s:show_previous_message()
  call s:focus_list_window()
 execute "normal k" 
 if line('.') != 1
   execute "normal \<cr>"
 endif
endfunction

" invoked from withint message window
function! s:show_raw()
  let command = s:lookup_command . s:current_uid . ' raw'
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
  end
  " set up syntax highlighting
  if has("syntax")
    syn clear
    syn match BufferFlagged /^.*[*].*$/hs=s
    hi def BufferFlagged ctermfg=red ctermbg=black
  endif
  if winnr("$") > 1
    wincmd p
    close!
  endif
  " vertically center the cursor line
  normal z.
endfunction

function! s:focus_message_window()
  let winnr = bufwinnr(s:message_window_bufnr)
  if winnr == -1
    " create window
    exec "split " . s:message_bufname
  else
    exec winnr . "wincmd w"
  endif
endfunction

" gets new messages since last update
function! s:update()
  let command = s:update_command
  echo command
  let res = system(command)
  if match(res, '^\d\+') != -1
    setlocal modifiable
    $put =res
    setlocal nomodifiable
    let num = len(split(res, '\n', ''))
    redraw
    echo "you have " . num . " new message(s)!"
  else
    redraw
    echo "no new messages"
  end
endfunction

function! s:toggle_flag(flag) range
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
  " check if starred already
  let flag_symbol = ''
  if a:flag == "Flagged"
    let flag_symbol = "[*]"
  end
  if (match(line, flag_symbol) != -1)
    let command = s:flag_command . uid_set . " -FLAGS " . a:flag
  else
    let command = s:flag_command . uid_set . " +FLAGS " . a:flag
  endif
  echo command
  " replace the lines with the returned results
  let res = system(command)
  setlocal modifiable
  exec a:firstline . "," . a:lastline . "delete"
  if a:flag != "Deleted"
    exec (a:firstline - 1). "put =res"
  end
  setlocal nomodifiable
endfunction

" --------------------------------------------------------------------------------
" move to another mailbox
function! s:move_to_mailbox() range
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
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>complete_move_to_mailbox()<CR> 
  inoremap <silent> <buffer> <esc> <Esc>:q<cr>
  set completefunc=CompleteMoveMailbox
  " c-p clears the line
  let s:firstline = a:firstline 
  let s:lastline = a:lastline
  call feedkeys("i\<c-x>\<c-u>\<c-p>", 't')
  " save these in script scope to delete the lines when move completes
endfunction

" Open command window to choose a mailbox to move a message to.
" Very similar to mailbox_window() function
function! s:complete_move_to_mailbox()
  let mailbox = getline(line('.'))
  close
  " check if mailbox is a real mailbox
  if (index(s:mailboxes, mailbox) == -1) 
    return
  endif
  let command = s:move_to_command . s:uid_set . ' ' . shellescape(mailbox)
  echo command
  let res = system(command)
  setlocal modifiable
  exec s:firstline . "," . s:lastline . "delete"
  setlocal nomodifiable
endfunction

function! CompleteMoveMailbox(findstart, base)
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  if a:findstart
    " locate the start of the word
    return 0
  else
    " find months matching with "a:base"
    let res = []
    for m in s:mailboxes
      if m == s:mailbox
        continue
      end
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

function! CompleteMailbox(findstart, base)
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  if a:findstart
    " locate the start of the word
    return 0
  else
    " find months matching with "a:base"
    let res = []
    for m in s:mailboxes
      if m =~ '^' . a:base
        call add(res, m)
      endif
    endfor
    return res
  endif
endfun

" -------------------------------------------------------------------------------
" select mailbox

function! s:mailbox_window()
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  topleft split MailboxSelect
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  resize 1
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>select_mailbox()<CR> 
  inoremap <silent> <buffer> <esc> <Esc>:q<cr>
  set completefunc=CompleteMailbox
  " c-p clears the line
  call feedkeys("i\<c-x>\<c-u>\<c-p>", 't')
endfunction

function! s:select_mailbox()
  let s:mailbox = getline(line('.'))
  close
  " check if mailbox is a real mailbox
  if (index(s:mailboxes, s:mailbox) == -1) 
    return
  endif
  let command = s:select_mailbox_command . shellescape(s:mailbox)
  echo command
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
  normal z-
endfunction

function! s:search_window()
  topleft split SearchWindow
  setlocal buftype=nofile
  setlocal noswapfile
  resize 1
  setlocal modifiable
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>do_search()<CR> 
  call feedkeys("i")
endfunction

function! s:do_search()
  let s:query = getline(line('.'))
  close
  " TODO should we really hardcode 100 as the quantity?
  let command = s:search_command . "100 " . shellescape(s:query)
  echo command
  call s:focus_list_window()  
  let res = system(command)
  setlocal modifiable
  1,$delete
  put! =res
  execute "normal Gdd\<c-y>" 
  normal G
  setlocal nomodifiable
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

function! s:compose_reply(all)
  " create a new window and close all others
  if a:all
    let command = s:reply_template_command . s:current_uid . ' 1'
  else
    let command = s:reply_template_command . s:current_uid
  end
  redraw
  echo command
  let res = system(command)
  only " make one pane first
  vertical split ComposeMessage
  only
  setlocal modifiable
  1,$delete
  put! =res
  normal 1G
  noremap <silent> <buffer> <Leader>d :call <SID>deliver_message()<CR>
  nnoremap <silent> <buffer> q :call <SID>cancel_compose()<cr>
  nnoremap <silent> <buffer> <leader>q :call <SID>cancel_compose()<cr>
endfunction

function! s:compose_message()
  write
  let command = s:message_template_command
  redraw
  echo command
  let res = system(command)
  only " make one pane first
  vertical split ComposeMessage
  only
  setlocal modifiable
  1,$delete
  put! =res
  normal 1G
  noremap <silent> <buffer> <Leader>d :call <SID>deliver_message()<CR>
  nnoremap <silent> <buffer> q :call <SID>cancel_compose()<cr>
  nnoremap <silent> <buffer> <leader>q :call <SID>cancel_compose()<cr>
endfunction

function! s:cancel_compose()
  call s:focus_list_window()
endfunction

function! s:deliver_message()
  w
  let mail = join(getline(1,'$'), "\n")
  exec ":!" . s:deliver_command . " < ComposeMessage" 
  redraw
  call s:focus_list_window()
endfunction

call s:create_list_window()

call s:create_message_window()

call s:focus_list_window() " to go list window
" this are list window bindings

noremap <silent> <buffer> <cr> :call <SID>show_message()<CR>
noremap <silent> <buffer> q :qal!<cr>

noremap <silent> <buffer> s :call <SID>toggle_flag("Flagged")<CR>
noremap <silent> <buffer> <leader>D :call <SID>toggle_flag("Deleted")<CR>
noremap <silent> <buffer> <leader>d :call <SID>toggle_flag("Deleted")<CR>
noremap <silent> <buffer> ! :call <SID>toggle_flag("[Gmail]/Spam")<CR>

"open a link browser (os x)
"autocmd CursorMoved <buffer> call <SID>show_message()

noremap <silent> <buffer> u :call <SID>update()<CR>
noremap <silent> <buffer> <Leader>s :call <SID>search_window()<CR>
noremap <silent> <buffer> <Leader>m :call <SID>mailbox_window()<CR>
noremap <silent> <buffer> <Leader>v :call <SID>move_to_mailbox()<CR>

noremap <silent> <buffer> <Leader>c :call <SID>compose_message()<CR><cr>



" press double return in list view to go full screen on a message; then
" return? again to restore the list view

" go to bottom
normal G
