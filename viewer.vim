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
let s:parsed_search_command = s:client_script . "parsed_search "
let s:flag_command = s:client_script . "flag "
let s:message_template_command = s:client_script . "message_template "
let s:reply_template_command = s:client_script . "reply_template "
let s:deliver_command = s:client_script . "deliver "
let s:message_bufname = "MessageWindow"
let s:list_bufname = "MessageListWindow"

function! s:set_parameters() 
  " TODO
  let s:mailbox = "INBOX" 
  let s:query = "all"
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
endfunction

" the message display buffer window
function! s:create_message_window() 
  exec "botright split " . s:message_bufname
  setlocal buftype=nofile
  " setlocal noswapfile
  " setlocal nobuflisted
  let s:message_window_bufnr = bufnr('%')
  " message window bindings
  noremap <silent> <buffer> <cr> :call <SID>focus_list_window()<CR> 
  noremap <silent> <buffer> <Leader>r :call <SID>compose_message(1)<CR><cr>
  noremap <silent> <buffer> <Leader>R :call <SID>show_raw()<cr>
  " TODO improve this
  noremap <silent> <buffer> <Leader>o yE :!open <C-R>"<CR><CR>

  close
endfunction

function! s:show_message()
  call s:focus_list_window()  
  let line = getline(line("."))
  let selected_uid = matchstr(line, '^\d\+')
  let s:current_uid = selected_uid
  let command = s:lookup_command . s:current_uid
  echo command
  call s:focus_message_window()
  setlocal modifiable
  1,$delete
  let res = system(command)
  put =res
  1delete
  normal 1
  normal jk
  wincmd p
  " flag as seen
  let line = getline(line('.'))
  let newline = substitute(line, "[]\.*$", "[:Seen]", '')
  setlocal modifiable
  call setline(line('.'), newline)
  setlocal nomodifiable
  write
  call feedkeys("<cr>")
  call s:focus_message_window()
  only
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
"    syn match BufferNormal /.*/
    syn match BufferFlagged /^.*:Flagged.*$/hs=s
"    hi def BufferNormal ctermfg=black ctermbg=white
    hi def BufferFlagged ctermfg=white ctermbg=black
  endif
  if winnr("$") > 1
    only
  endif
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
  let flag_symbol = ":" . a:flag
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

function! s:mailbox_window()
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  vne Mailboxes
  setlocal buftype=nofile
  setlocal noswapfile
  vertical resize 25
  put! = s:mailboxes 
  normal 1G
  noremap <silent> <buffer> <cr> <Esc>:call <SID>select_mailbox()<CR> 
endfunction

function! s:select_mailbox()
  let s:mailbox = getline(line('.'))
  close
  let command = s:select_mailbox_command . shellescape(s:mailbox)
  echo command
  call system(command)
  redraw
  " now get latest 100 messages
  call s:focus_list_window()  
  set modifiable
  let command = s:search_command . "100 all"
  echo command
  let res = system(command)
  1,$delete
  put! =res
  execute "normal Gdd\<c-y>" 
  normal G
  set nomodifiable
endfunction

function! s:search_window()
  topleft split SearchWindow
  setlocal buftype=nofile
  setlocal noswapfile
  resize 1
  setlocal modifiable
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>do_search()<CR> 
  set completefunc=CompleteMailbox
  call feedkeys("$i")
endfunction

function! s:do_search()
  let s:query = getline(line('.'))
  close
  let command = s:parsed_search_command . shellescape(s:query)
  echo command
  call s:focus_list_window()  
  let res = system(command)
  set modifiable
  1,$delete
  put! =res
  execute "normal Gdd\<c-y>" 
  normal G
  set nomodifiable
endfunction

function! s:compose_message(isreply)
  " create a new window and close all others
  if a:isreply 
    let command = s:reply_template_command . s:current_uid
  else
    let command = s:message_template_command
  end
  redraw
  echo command
  let res = system(command)
  only " make one pane first
  vertical botright split ComposeMessage
  only
  setlocal modifiable
  1,$delete
  put! =res
  normal 1G
  noremap <silent> <buffer> <Leader>d :call <SID>deliver_message()<CR>
  nnoremap <silent> <buffer> q :q!<cr>:call <SID>focus_list_window()<cr>
endfunction

function! s:deliver_message()
  w
  let mail = join(getline(1,'$'), "\n")
  exec ":!" . s:deliver_command . " < ComposeMessage" 
  "call system(s:deliver_command, mail)
  redraw
"  echo res
endfunction

call s:create_list_window()

call s:create_message_window()

call s:focus_list_window() " to go list window
" this are list window bindings

noremap <silent> <buffer> <cr> :call <SID>show_message()<CR>
noremap <silent> q :qal!<cr>

noremap <silent> <buffer> s :call <SID>toggle_flag("Flagged")<CR>
noremap <silent> <buffer> D :call <SID>toggle_flag("Deleted")<CR>
noremap <silent> <buffer> ! :call <SID>toggle_flag("[Gmail]/Spam")<CR>

"open a link browser (os x)
"autocmd CursorMoved <buffer> call <SID>show_message()

noremap <silent> <buffer> u :call <SID>update()<CR>
noremap <silent> <buffer> <Leader>s :call <SID>search_window()<CR>
noremap <silent> <buffer> <Leader>m :call <SID>mailbox_window()<CR><CR>

noremap <silent> <buffer> <Leader>c :call <SID>compose_message(0)<CR><cr>


" press double return in list view to go full screen on a message; then
" return? again to restore the list view

" go to bottom
normal G
