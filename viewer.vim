let s:mailbox = ''
let s:num_msgs = 0 " number of messages
let s:query = ''

let s:lookup_command = "ruby lib/client.rb lookup "
let s:select_mailbox_command = "ruby lib/client.rb select_mailbox "
let s:search_command = "ruby lib/client.rb search "


function! s:SetParameters() 
  let s:mailbox = getline(1)
  let s:num_msgs = getline(2)
  let s:query = getline(3)
endfunction

function! s:CreateListWindow()
  "setlocal bufhidden=delete
  "setlocal buftype=nofile
  " setlocal nomodifiable
  setlocal noswapfile
  "setlocal nomodifiable
  setlocal nowrap
  setlocal nonumber
  setlocal foldcolumn=0
  setlocal nospell
  setlocal nobuflisted
  setlocal textwidth=0
  setlocal noreadonly
  " hi CursorLine cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white 
  setlocal cursorline
  let s:listbufnr = bufnr('%')
endfunction


" the message display buffer window
function! s:CreateMessageWindow() 
  split Message
  setlocal buftype=nofile
  setlocal noswapfile
  let s:message_window_bufnr = bufnr('%')
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
  let window_nr = bufwinnr(s:message_window_bufnr)
  exec window_nr . "wincmd w"
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


call s:CreateListWindow()

" Detail Window is on top, to buck the trend!
call s:CreateMessageWindow()

call s:focus_list_window() " to go list window

noremap <silent> <buffer> <cr> :call <SID>ShowMessage(0)<CR> 
noremap <silent> <buffer> r :call <SID>ShowMessage(1)<CR> 
noremap <silent> <buffer> f :call <SID>GetMessages()<CR> 

"autocmd CursorMoved <buffer> call <SID>ShowMessage()

