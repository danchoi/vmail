function! s:CreateListWindow()
  setlocal bufhidden=delete
  setlocal buftype=nofile
  " setlocal nomodifiable
  setlocal noswapfile
  setlocal nomodifiable
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

call s:CreateListWindow()

" the message display buffer window
function! s:CreateDetailWindow() 
  split Message
  setlocal buftype=nofile
  setlocal noswapfile
  let s:messagebufnr = bufnr('%')
endfunction

let s:lookup_command = "ruby lib/client.rb "

function! s:ShowMessage(raw)
  " TODO change me
  2 wincmd w  
  let s:selected_mailbox = getline(1) 
  let line = getline(line("."))
  let message_uid = matchstr(line, '^\d\+')
  if a:raw
    let command = s:lookup_command . message_uid . " raw"
  else
    let command = s:lookup_command . message_uid
  endif
  echo command
  let res = system(command)
  1 wincmd w
  1,$delete
  put =res
  1delete
  normal 1
  normal jk
  wincmd p
  " 1 wincmd w
endfunction

call s:CreateListWindow()

" Detail Window is on top, to buck the trend!
call s:CreateDetailWindow()

2 wincmd w " to go list window
noremap <silent> <buffer> <cr> :call <SID>ShowMessage(0)<CR> 
noremap <silent> <buffer> r :call <SID>ShowMessage(1)<CR> 

"autocmd CursorMoved <buffer> call <SID>ShowMessage()

