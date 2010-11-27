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

function! s:ShowMessage()
  " TODO change me
  let s:selected_mailbox = "INBOX"
  2 wincmd w  
  let line = getline(line("."))
  let message_uid = matchstr(line, '^\d\+')
  let command = "ruby lib/gmail.rb " . shellescape(s:selected_mailbox) . " " . message_uid
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
noremap <silent> <buffer> <cr> :call <SID>ShowMessage()<CR> 

"autocmd CursorMoved <buffer> call <SID>ShowMessage()

