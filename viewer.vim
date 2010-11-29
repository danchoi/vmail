let s:mailbox = ''
let s:num_msgs = 0 " number of messages
let s:query = ''

let s:lookup_command = "ruby lib/client.rb lookup "
let s:select_mailbox_command = "ruby lib/client.rb select_mailbox "
let s:search_command = "ruby lib/client.rb search "
let s:flag_command = "ruby lib/client.rb flag "
let s:message_bufname = "MessageWindow"

function! s:SetParameters() 
  let s:mailbox = getline(1)
  let s:num_msgs = getline(2)
  let s:query = getline(3)
endfunction

function! s:CreateListWindow()
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
function! s:CreateMessageWindow() 
  exec "split " . s:message_bufname
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nobuflisted
  let s:message_window_bufnr = bufnr('%')
  close
endfunction

function! s:ShowMessage(raw)
  " TODO change me
  call s:focus_list_window()  
  let line = getline(line("."))
  let message_uid = matchstr(line, '^\d\+')
  if a:raw
    let command = s:lookup_command . message_uid . " raw"
  else
    let command = s:lookup_command . message_uid
  endif
  echo command
  let res = system(command)
  call s:focus_message_window()
  1,$delete
  put =res
  1delete
  normal 1
  normal jk
  wincmd p
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

function! s:GetMessages()
  call s:focus_list_window()
  call s:SetParameters()
  let command = s:select_mailbox_command .  shellescape(s:mailbox) 
  echo command
  call system(command)
  let command = s:search_command . s:num_msgs . " " . shellescape(s:query) 
  echo command
  let res =  system(command)
  4,$delete
  put =res
  normal 4
  normal jk
endfunction


function! s:toggle_flag(flag)
  let line = getline(line("."))
  let message_uid = matchstr(line, '^\d\+')
  " check if starred already
  let flag_symbol = ":" . a:flag
  if (match(line, flag_symbol) != -1)
    let command = s:flag_command . message_uid . " -FLAGS " . a:flag
  else
    let command = s:flag_command . message_uid . " +FLAGS " . a:flag
  endif
  echo command
  " replace the line with the returned result
  let res = system(command)
  setlocal modifiable
  if match(res, '^\d\+ deleted') != -1
    exec line('.') . 'delete'
  else
    exec line(".") . "put! =res"
    exec (line(".") + 1) . "delete"
  end
  setlocal nomodifiable
endfunction

call s:CreateListWindow()

" Detail Window is on top, to buck the trend!
call s:CreateMessageWindow()

call s:focus_list_window() " to go list window

noremap <silent> <buffer> <cr> :call <SID>ShowMessage(0)<CR> 
noremap <silent> <buffer> r :call <SID>ShowMessage(1)<CR> 
noremap <silent> q :qal!<cr>

noremap <silent> <buffer> s :call <SID>toggle_flag("Flagged")<CR>
noremap <silent> <buffer> d :call <SID>toggle_flag("Deleted")<CR>
noremap <silent> <buffer> ! :call <SID>toggle_flag("[Gmail]/Spam")<CR>

"open a link browser (os x)
noremap <silent> o yE :!open <C-R>"<CR>
"autocmd CursorMoved <buffer> call <SID>ShowMessage()

" noremap <silent> <buffer> f :call <SID>GetMessages()<CR> 

