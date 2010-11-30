let s:mailbox = ''
let s:num_msgs = 0 " number of messages
let s:query = ''

let s:drb_uri = getline(1)

let s:client_script = "ruby lib/client.rb " . s:drb_uri . " "
let s:list_mailboxes_command = s:client_script . "list_mailboxes "
let s:lookup_command = s:client_script . "lookup "
let s:update_command = s:client_script . "update"
let s:fetch_headers_command = s:client_script . "fetch_headers "
let s:select_mailbox_command = s:client_script . "select_mailbox "
let s:search_command = s:client_script . "search "
let s:flag_command = s:client_script . "flag "
let s:message_bufname = "MessageWindow"

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

  " set up syntax highlighting
  if has("syntax")
    syn clear
"    syn match BufferNormal /.*/
    syn match BufferFlagged /^.*:Flagged.*$/hs=s
"    hi def BufferNormal ctermfg=black ctermbg=white
    hi def BufferFlagged ctermfg=white ctermbg=black
  endif
endfunction

" the message display buffer window
function! s:create_message_window() 
  exec "split " . s:message_bufname
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nobuflisted
  let s:message_window_bufnr = bufnr('%')
  close
endfunction

function! s:show_message(raw)
  call s:focus_list_window()  
  let line = getline(line("."))
  let message_uid = matchstr(line, '^\d\+')
  if a:raw
    let command = s:lookup_command . message_uid . " raw"
  else
    let command = s:lookup_command . message_uid
  endif
  echo command

  call s:focus_message_window()
  set modifiable
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
  set modifiable
  call setline(line('.'), newline)
  set nomodifiable
  " call s:focus_message_window()
endfunction

function! s:focus_list_window()
  let window_nr = bufwinnr(s:listbufnr) 
  exec window_nr . "wincmd w"
endfunction

function! s:focus_message_window()
  let winnr = bufwinnr(s:message_window_bufnr)
  if winnr == -1
    " create window
    exec "split " . s:message_bufname
  endif
  exec winnr . "wincmd w"
endfunction

" don't use this yet
function! s:get_messages()
  call s:focus_list_window()
  call s:set_parameters()
  let command = s:select_mailbox_command .  shellescape(s:mailbox) 
  " echo command
  call system(command)
  " get window height
  let s:limit = winheight(bufwinnr(s:listbufnr)) 
  if !exists('s:offset')
    let s:offset = (line('w$') - 1) - s:limit
  endif
  let command = s:search_command . s:limit . " " . s:offset . " " . shellescape(s:query) 
  echo command
  let res =  system(command)
  set modifiable
  let lines =  split(res, "\n")
  call append(0, lines)
  " execute "normal Gdd\<c-y>" 
  set nomodifiable
  " move offset back
  let s:offset = s:offset - s:limit
endfunction

" gets new messages since last update
function! s:update()
  let command = s:update_command
  echo command
  let res = system(command)
  if match(res, '^\d\+') != -1
    set modifiable
    $put =res
    set nomodifiable
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
      if m =~ '^' . a:base
        call add(res, m)
      endif
    endfor
    return res
  endif
endfun

function! s:select_mailbox()
  topleft split SelectMailbox
  setlocal buftype=nofile
  setlocal noswapfile
  resize 1
  set modifiable
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>close_mailbox_list()<CR> 
  " autocmd CursorMovedI <buffer>  call feedkeys("i\<c-x>\<c-u>")
  set completefunc=CompleteMailbox
  call feedkeys("i\<c-x>\<c-u>")
endfunction

function! s:close_mailbox_list()
  let selection = getline(line('.'))
  bdelete
  redraw
  echo selection
endfunction

call s:create_list_window()

" Detail Window is on top, to buck the trend!
call s:create_message_window()

call s:focus_list_window() " to go list window


noremap <silent> <buffer> <cr> :call <SID>show_message(0)<CR> 
noremap <silent> <buffer> r :call <SID>show_message(1)<CR> 
noremap <silent> q :qal!<cr>

noremap <silent> <buffer> s :call <SID>toggle_flag("Flagged")<CR>
noremap <silent> <buffer> D :call <SID>toggle_flag("Deleted")<CR>
noremap <silent> <buffer> ! :call <SID>toggle_flag("[Gmail]/Spam")<CR>

"open a link browser (os x)
noremap <silent> o yE :!open <C-R>"<CR><CR>
"autocmd CursorMoved <buffer> call <SID>show_message()

"noremap <silent> <buffer> f :call <SID>get_messages()<CR><PageUp>
noremap <silent> <buffer> u :call <SID>update()<CR>
noremap <silent> <buffer> <Leader>m :call <SID>select_mailbox()<CR>

" noremap <silent> <buffer> f :call <SID>get_messages()<CR> 

" get messages

" delete the drb url line
set modifiable
1delete
w
set nomodifiable

" go to bottom
normal G
