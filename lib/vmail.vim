"=================================================
" File: vmail.vim
" Description: Vmail is a Vim interface to Gmail.
" Author: Daniel Choi
" ================================================

if exists("g:loaded_vmail") || &cp
    finish
endif
let g:loaded_vmail = 1

if !exists("g:vmail_flagged_color")
  let g:vmail_flagged_color = "ctermfg=green guifg=green guibg=grey"
endif
let s:mailbox = $VMAIL_MAILBOX
let s:query = $VMAIL_QUERY
let s:browser_command = $VMAIL_BROWSER
let s:append_file = ''

let s:drb_uri = $DRB_URI

let s:client_script = "vmail_client " . shellescape(s:drb_uri) . " "
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
let s:save_attachments_command = s:client_script . "save_attachments "
let s:open_html_part_command = s:client_script . "open_html_part "
let s:show_help_command = s:client_script . "show_help"

let s:message_bufname = "current_message.txt"

function! VmailStatusLine()
  return "%<%f\ " . s:mailbox . " " . s:query . "%r%=%-14.(%l,%c%V%)\ %Y %P"
endfunction

function! s:create_list_window()
  setlocal nomodifiable
  setlocal noswapfile
  setlocal nowrap
  setlocal nonumber
  setlocal foldcolumn=0
  setlocal nospell
  setlocal textwidth=0
  setlocal noreadonly
  setl ft=mail

  " let user set this
  " setlocal cursorline
  " we need the bufnr to find the window later
  let s:listbufnr = bufnr('%')
  let s:listbufname = bufname('%')
  setlocal statusline=%!VmailStatusLine()
  call s:message_list_window_mappings()
  setlocal filetype=vmail
  autocmd BufNewFile,BufRead *.txt setlocal modifiable
endfunction

" the message display buffer window
function! s:create_message_window() 
  exec "split " . s:message_bufname
  setlocal modifiable 
  setlocal buftype=nofile
  let s:message_window_bufnr = bufnr('%')
  call s:message_window_mappings()
  close
endfunction

function! s:system_with_error_handling(command)
  let res = system(a:command)
  if res =~ 'VMAIL_ERROR'
    echoe "ERROR" res
    return ""
  else
    return res
  end
endfunction

function! s:show_message(stay_in_message_list)
  let line = getline(line("."))
  if match(line, '^>  Load') != -1
    setlocal modifiable
    delete
    call s:more_messages()
    return
  endif
  let s:uid = shellescape(matchstr(line, '\S\+$'))
  if s:uid == ""
    return
  end
  " mark as read
  let newline = substitute(line, '^\V*+', '* ', '')
  let newline = substitute(newline, '^\V+ ', '  ', '')
  setlocal modifiable
  call setline(line('.'), newline)
  setlocal nomodifiable
  write
  " this just clears the command line and prevents the screen from
  " moving up when the next echo statement executes:
  " call feedkeys(":\<cr>") 
  " redraw
  let command = s:show_message_command . s:uid
  echom "Loading message ". s:uid .". Please wait..."
  redrawstatus
  let res = s:system_with_error_handling(command)
  call s:focus_message_window()
  set modifiable
  1,$delete
  put =res
  " critical: don't call execute 'normal \<cr>'
  " call feedkeys("<cr>") 
  1delete
  normal 1Gjk
  set nomodifiable
  if a:stay_in_message_list
    call s:focus_list_window()
  end
  redraw
endfunction

" from message window
function! s:show_next_message()
  let fullscreen = (bufwinnr(s:listbufnr) == -1) " we're in full screen message mode
  if fullscreen
    3split
    exec 'b'. s:listbufnr
  else
    call s:focus_list_window()
  end
  normal j
  call s:show_message(1)
  normal zz
  wincmd p
  redraw
endfunction

function! s:show_previous_message()
  let fullscreen = (bufwinnr(s:listbufnr) == -1) " we're in full screen message mode
  if fullscreen
    3split 
    exec 'b'. s:listbufnr
  else
    call s:focus_list_window()
  end
  normal k
  if line('.') != line('$')
    call s:show_message(1)
  endif
  normal zz
  wincmd p
  redraw
endfunction


" from message list window
function! s:show_next_message_in_list()
  if line('.') != line('$')
    normal j
    call s:show_message(1)
  endif
endfunction

function! s:show_previous_message_in_list()
  if line('.') != 1
    normal k
    call s:show_message(1)
  endif
endfunction


" invoked from withint message window
function! s:show_raw()
  let command = s:show_message_command . s:uid . ' raw'
  echo command
  setlocal modifiable
  1,$delete
  let res = s:system_with_error_handling(command)
  put =res
  1delete
  normal 1G
  setlocal nomodifiable
endfunction

function! s:focus_list_window()
  if bufwinnr(s:listbufnr) == winnr() 
    return
  end
  let winnr = bufwinnr(s:listbufnr) 
  if winnr == -1
    " create window
    split
    exec "buffer" . s:listbufnr
  else
    exec winnr . "wincmd w"
  endif
  " call feedkeys("\<c-l>") " prevents screen artifacts when user presses return too fast
  " turn this off though, because it causes an annoying flash
endfunction


function! s:focus_message_window()
  let winnr = bufwinnr(s:message_window_bufnr)
  if winnr == -1
    " create window
    exec "rightbelow split " . s:message_bufname
  else
    exec winnr . "wincmd w"
  endif
endfunction

func! s:close_message_window()
  if winnr('$') > 1
    close!
  else
    call s:focus_list_window()
    wincmd p
    close!
    normal z.
  endif
endfunc

" gets new messages since last update
function! s:update()
  let command = s:update_command
  echo "Checking for new messages. Please wait..."
  let res = s:system_with_error_handling(command)
  let lines = split(res, '\n')
  if len(lines) > 0
    setlocal modifiable
    call append(0, lines)
    setlocal nomodifiable
    write!
    let num = len(lines)
    call cursor(num, 0)
    normal z.
    redraw
    echom "You have " . num . " new message" . (num == 1 ? '' : 's') . "!" 
  else
    redraw
    echom "No new messages"
  endif
endfunction

" function argument a:read: Represents the next state
" 0 means unread, 1 means read.
function! s:mark_as_read_unread(read) range
  let uid_set = s:collect_uids(a:firstline, a:lastline)
  let nummsgs = len(uid_set)
  " decide whether to set messages to SEEN or UNSEEN
  let action = (a:read ? " +" : " -") . "FLAGS"
  " construct the imap command
  let command = s:flag_command . shellescape(join(uid_set, ',')) . action . " SEEN"
  " do the real imap flagging
  let res = s:system_with_error_handling(command)
  setlocal modifiable
  let lnum = a:firstline
  while lnum <= a:lastline
    let line = getline(lnum)
    if action ==# " +FLAGS"
      let newline = substitute(line, '^*+', '* ', '')
      let newline = substitute(newline, '^+ ', '  ', '')
    else
      let newline = substitute(line, '^ ', '+', '')
      let newline = substitute(newline, '^\* ', '*+', '')
    endif
    call setline(lnum, newline)
    let lnum += 1
  endwhile
  setlocal nomodifiable
  write
  redraw
  echom nummsgs  ." conversation(s) have been marked as unread."
endfunction

function! s:toggle_star() range
  let uid_set = s:collect_uids(a:firstline, a:lastline)
  let nummsgs = len(uid_set)
  let flag_symbol = "^*"
  " check if starred already
  let action = " +FLAGS"
  if (match(getline(a:firstline), flag_symbol) != -1)
    let action = " -FLAGS"
  endif
  let command = s:flag_command . shellescape(join(uid_set, ',')) . action . " Flagged" 
  if nummsgs == 1
    echom "Toggling flag on message" 
  else
    echom "Toggling flags on " . nummsgs . " messages"
  endif
  " toggle * on lines
  let res = s:system_with_error_handling(command)
  setlocal modifiable
  let lnum = a:firstline
  while lnum <= a:lastline
    let line = getline(lnum)
    if action == " +FLAGS"
      let newline = substitute(line, '^ ', '*', '')
      let newline = substitute(newline, '^+ ', '*+', '')
    else
      let newline = substitute(line, '^*+', '+ ', '')
      let newline = substitute(newline, '^* ', '  ', '')
    endif
    call setline(lnum, newline)
    let lnum += 1
  endwhile
  setlocal nomodifiable
  write
  redraw
  if nummsgs == 1
    echom "Toggled flag on message" 
  else
    echom "Toggled flags on " . nummsgs . " messages"
  endif
endfunction

" flag can be Deleted or spam
func! s:delete_messages(flag) range
  let uid_set = s:collect_uids(a:firstline, a:lastline)
  let nummsgs = len(uid_set)
  let command = s:flag_command . shellescape(join(uid_set, ',')) . " +FLAGS " . a:flag
  if nummsgs == 1
    echom "Deleting message" 
  else
    echom "Deleting " . nummsgs . " messages"
  endif
  let res = s:system_with_error_handling(command)
  setlocal modifiable
  exec "silent " . a:firstline . "," . a:lastline . "delete"
  setlocal nomodifiable
  write
  redraw
  echo nummsgs .  " message" . (nummsgs == 1 ? '' : 's') . " marked " . a:flag
endfunc

func! s:archive_messages() range
  let uid_set = s:collect_uids(a:firstline, a:lastline)
  let nummsgs = len(uid_set)
  let command = s:move_to_command . shellescape(join(uid_set, ',')) . ' ' . "all"
  echo "Archiving message" . (nummsgs == 1 ? '' : 's')
  let res = s:system_with_error_handling(command)
  setlocal modifiable
  exec "silent " . a:firstline . "," . a:lastline . "delete"
  setlocal nomodifiable
  write
  redraw
  echo nummsgs . " message" . (nummsgs == 1 ? '' : 's') . " archived"
endfunc

" --------------------------------------------------------------------------------

" append text bodies of a set of messages to a file
func! s:append_messages_to_file() range
  let uid_set = s:collect_uids(a:firstline, a:lastline)
  let nummsgs = len(uid_set)
  let append_file = input("print messages to file: ", s:append_file)
  if append_file == ''
    echom "Canceled"
    return
  endif
  let s:append_file = append_file
  let command = s:append_to_file_command . shellescape(join(uid_set, ',')) . ' ' . s:append_file 
  echo "Appending " . nummsgs . " message" . (nummsgs == 1 ? '' : 's') . " to " . s:append_file . ". Please wait..."
  let res = s:system_with_error_handling(command)
  echo res
  redraw
endfunc

" --------------------------------------------------------------------------------
" move to another mailbox
function! s:move_to_mailbox(copy) range
  let s:copy_to_mailbox = a:copy
  let uid_set = s:collect_uids(a:firstline, a:lastline)
  let s:nummsgs = len(uid_set)
  let s:uid_set = shellescape(join(uid_set, ','))
  " now prompt use to select mailbox
  if !exists("s:mailboxes")
    call s:get_mailbox_list()
  endif
  leftabove split MailboxSelect
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  resize 1
  let prompt = "select mailbox to " . (a:copy ? 'copy' : 'move') . " to: "
  call setline(1, prompt)
  normal $
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>complete_move_to_mailbox()<CR> 
  inoremap <silent> <buffer> <esc> <Esc>:q<cr>
  setlocal completefunc=CompleteMoveMailbox
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
  echo "Moving uids ". s:uid_set . " to mailbox " . mailbox 
  let res = s:system_with_error_handling(command)
  setlocal modifiable
  if !s:copy_to_mailbox
    exec "silent " . s:firstline . "," . s:lastline . "delete"
  end
  setlocal nomodifiable
  write
  redraw
  echo s:nummsgs .  " message" . (s:nummsgs == 1 ? '' : 's') . ' ' . (s:copy_to_mailbox ? 'copied' : 'moved') . ' to ' . mailbox 
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
  let res = s:system_with_error_handling(command)
  let s:mailboxes = split(res, "\n", '')
endfunction

" -------------------------------------------------------------------------------
" select mailbox

function! s:mailbox_window()
  call s:get_mailbox_list()
  leftabove split MailboxSelect
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal modifiable
  resize 1
  inoremap <silent> <buffer> <cr> <Esc>:call <SID>select_mailbox()<CR> 
  inoremap <silent> <buffer> <esc> <Esc>:q<cr>
  setlocal completefunc=CompleteMailbox
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
  " check if mailbox is a real mailbox
  if (index(s:mailboxes, mailbox) == -1)
    return
  endif
  let s:mailbox = mailbox
  let s:query = "all"
  let command = s:select_mailbox_command . shellescape(s:mailbox)
  redraw
  echom "Selecting mailbox: ". s:mailbox . ". Please wait..."
  call s:system_with_error_handling(command)
  redraw
  " reset window width now
  call s:system_with_error_handling(s:set_window_width_command . winwidth(1))
  " now get latest 100 messages
  call s:focus_list_window()  
  setlocal modifiable
  let command = s:search_command . shellescape("all")
  echo "Loading messages..."
  let res = s:system_with_error_handling(command)
  silent 1,$delete
  silent! put! =res
  execute "normal Gdd\<c-y>" 
  setlocal nomodifiable
  write
  normal gg
  redraw
  echom "Current mailbox: ". s:mailbox 
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
  let command = s:search_command . shellescape(s:query)
  redraw
  call s:focus_list_window()  
  setlocal modifiable
  echo "Running query on " . s:mailbox . ": " . s:query . ". Please wait..."
  let res = s:system_with_error_handling(command)
  silent! 1,$delete
  silent! put! =res
  execute "silent normal Gdd\<c-y>" 
  setlocal nomodifiable
  write
  normal gg
endfunction

function! s:more_messages()
  let command = s:more_messages_command 
  echo "Fetching more messages. Please wait..."
  let res = s:system_with_error_handling(command)
  setlocal modifiable
  let lines =  split(res, "\n")
  call append(line('$'), lines)
  " execute "normal Gdd\<c-y>" 
  setlocal nomodifiable
  normal j
  redraw
  echo "Done"
endfunction

" --------------------------------------------------------------------------------  
"  compose reply, compose, forward, save draft

function! s:compose_reply(all)
  let command = s:reply_template_command 
  if a:all
    let command = command . ' 1'
  endif
  call s:open_compose_window(command)
  " cursor after headers
  normal 1G}
endfunction

function! s:compose_message()
  let command = s:new_message_template_command
  call s:open_compose_window(command)
  " position cursor after to:
"  call search("^to:") 
"  normal A
endfunction

function! s:compose_forward()
  let command = s:forward_template_command 
  call s:open_compose_window(command)
"  call search("^to:") 
"  normal A
endfunction

func! s:open_compose_window(command)
  redraw
  echo a:command
  let res = s:system_with_error_handling(a:command)
  let previous_winnr = winnr()
  only
  split compose_message.txt
  setlocal modifiable
  wincmd p
  close!
  silent! 1,$delete
  silent! put! =res
  redraw
  "call feedkeys("\<cr>")
  call s:compose_window_mappings()
  setlocal completefunc=CompleteContact
  normal 1G
endfunc

func! s:turn_into_compose_window()
  call s:compose_window_mappings()
  setlocal completefunc=CompleteContact
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
    " find contacts 
    " model regex: match at beginning of line, or inside < > wrapping
    " email addr
    "  '\(^ho\|<ho\)'
    " let regex = shellescape('\(^' . a:base . '\|<' . a:base . '\)')
    let regex = shellescape(a:base)
    let matches = s:system_with_error_handling("grep -i " . regex  . " " . $VMAIL_CONTACTS_FILE)
    return split(matches, "\n")
  endif
endfun

func! s:close_and_focus_list_window()
  call s:focus_list_window()
  wincmd p
  close!
  normal z.
endfunc


function! s:send_message()
  let mail = join(getline(1,'$'), "\n")
  echo "Sending message"
  let res = system(s:deliver_command, mail)
  if match(res, '^Failed') == -1
    write!
    call s:close_and_focus_list_window()
  endif
  echom substitute(res, '[\s\r\n]\+$', '', '')
  redraw
endfunction

" -------------------------------------------------------------------------------- 

" call from inside message window with <Leader>h
func! s:open_html_part()
  let command = s:open_html_part_command 
  " the command saves the html part to a local file
  let outfile = s:system_with_error_handling(command)
  " todo: allow user to change open in browser command?
  exec "!" . s:browser_command . ' ' . outfile
endfunc

func! s:save_attachments()
  if !exists("s:savedir")
    let s:savedir = getcwd() . "/attachments"
  end
  let s:savedir = input("save attachments to directory: ", s:savedir, "dir")
  let command = s:save_attachments_command . s:savedir
  let res = s:system_with_error_handling(command)
  echo res
endfunc

func! s:attach_file(file)
  normal gg
  normal }
  let attach = "attach: " . a:file
  put =attach
endfunc


" -------------------------------------------------------------------------------- 

func! s:toggle_maximize_window()
  if winnr('$') > 1
    only
    " normal z.
  elseif bufwinnr(s:listbufnr) == winnr()
    call s:show_message(1)
  else " we're in the message window
    call s:focus_list_window()
    wincmd p
  endif
endfunc

" maybe not DRY enough, but fix that later
" also, come up with a more precise regex pattern for matching hyperlinks
func! s:open_href(all) range
  let pattern = 'https\?:[^ >)\]]\+'
  let n = 0
  " range version
  if a:firstline < a:lastline
    let lnum = a:firstline
    while lnum <= a:lastline
      let href = matchstr(getline(lnum), pattern)
      if href != ""
        let command = s:browser_command ." ".shellescape(href)." &"
        call s:system_with_error_handling(command)
        let n += 1
      endif
      let lnum += 1
    endwhile
    echom 'opened '.n.' links' 
    return
  end
  let line = search(pattern, 'cw')
  if line && a:all
    while line
      let href = matchstr(getline(line('.')), pattern)
      let command = s:browser_command ." ".shellescape(href)." &"
      call s:system_with_error_handling(command)
      let n += 1
      let line = search('https\?:', 'W')
    endwhile
    echom 'opened '.n.' links' 
  else
    let href = matchstr(getline(line('.')), pattern)
    let command = s:browser_command ." ".shellescape(href)." &"
    call s:system_with_error_handling(command)
    echom 'opened '.href
  endif
endfunc

" -------------------------------------------------------------------------------- 
"  HELP
func! s:show_help()
  let command = s:browser_command . ' ' . shellescape('http://danielchoi.com/software/vmail.html')
  call s:system_with_error_handling(command)
  "let helpfile = s:system_with_error_handling(s:show_help_command)
  "exec "split " . helpfile
endfunc

" -------------------------------------------------------------------------------- 
" CONVENIENCE FUNCS

function! s:collect_uids(startline, endline)
  let uid_set = []
  let lnum = a:startline
  while lnum <= a:endline
    let uid = matchstr(getline(lnum), '\S\+$')
    call add(uid_set, uid)
    let lnum += 1
  endwhile
  return uid_set
endfunc

" -------------------------------------------------------------------------------- 
" MAPPINGS

func! s:message_window_mappings()
  if !hasmapto('<Plug>VmailMessageWindow_FocusListWindow')
    nmap <buffer> <CR> <Plug>VmailMessageWindow_FocusListWindow
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_FocusListWindow <C-W>=:call <SID>focus_list_window()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_Reply')
    nmap <buffer> <leader>r <Plug>VmailMessageWindow_Reply
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_Reply :call <SID>compose_reply(0)<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ReplyToAll')
    nmap <buffer> <leader>a <Plug>VmailMessageWindow_ReplyToAll
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ReplyToAll :call <SID>compose_reply(1)<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ShowRaw')
    nmap <buffer> <leader>R <Plug>VmailMessageWindow_ShowRaw
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ShowRaw :call <SID>show_raw()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_Forward')
    nmap <buffer> <leader>f <Plug>VmailMessageWindow_Forward
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_Forward :call <SID>compose_forward()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ShowNext')
    nmap <buffer> <C-j> <Plug>VmailMessageWindow_ShowNext
    nmap <buffer> <leader>j <Plug>VmailMessageWindow_ShowNext
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ShowNext :call <SID>show_next_message()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ShowPrev')
    nmap <buffer> <C-k> <Plug>VmailMessageWindow_ShowPrev
    nmap <buffer> <leader>k <Plug>VmailMessageWindow_ShowPrev
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ShowPrev :call <SID>show_previous_message()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ComposeMessage')
    nmap <buffer> <leader>c <Plug>VmailMessageWindow_ComposeMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ComposeMessage :call <SID>compose_message()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_OpenHTML')
    nmap <buffer> <leader>h <Plug>VmailMessageWindow_OpenHTML
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_OpenHTML :call <SID>open_html_part()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_CloseWindow')
    nmap <buffer> <leader>q <Plug>VmailMessageWindow_CloseWindow
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_CloseWindow :call <SID>close_message_window()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_DeleteMessage')
    nmap <buffer> <leader># <Plug>VmailMessageWindow_DeleteMessage
    nmap <buffer> <leader>3 <Plug>VmailMessageWindow_DeleteMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_DeleteMessage :close<cr>:call <SID>focus_list_window()<CR>:call <SID>delete_messages("Deleted")<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ToggleStar')
    nmap <buffer> <leader>* <Plug>VmailMessageWindow_ToggleStar
    nmap <buffer> <leader>8 <Plug>VmailMessageWindow_ToggleStar
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ToggleStar :call <SID>focus_list_window()<cr>:call <SID>toggle_star()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_MarkAsRead')
    nmap <buffer> I <Plug>VmailMessageWindow_MarkAsRead
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_MarkAsRead :call <SID>focus_list_window()<cr>:call <SID>mark_as_read_unread(1)<CR>

  if !hasmapto('<Plug>VmailMessageWindow_MarkAsUnread')
    nmap <buffer> U <Plug>VmailMessageWindow_MarkAsUnread
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_MarkAsUnread :call <SID>focus_list_window()<cr>:call <SID>mark_as_read_unread(1)<CR>

  if !hasmapto('<Plug>VmailMessageWindow_MarkAsSpam')
    nmap <buffer> <leader>! <Plug>VmailMessageWindow_MarkAsSpam
    nmap <buffer> <leader>1 <Plug>VmailMessageWindow_MarkAsSpam
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_MarkAsSpam :close<cr>:call <SID>focus_list_window()<cr>:call <SID>delete_messages("spam")<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ArchiveMessage')
    nmap <buffer> <leader>e <Plug>VmailMessageWindow_ArchiveMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ArchiveMessage :call <SID>focus_list_window()<cr>:call <SID>archive_messages()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_MoveToMailbox')
    nmap <buffer> <leader>b <Plug>VmailMessageWindow_MoveToMailbox
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_MoveToMailbox :call <SID>focus_list_window()<cr>:call <SID>move_to_mailbox(0)<CR>

  if !hasmapto('<Plug>VmailMessageWindow_CopyToMailbox')
    nmap <buffer> <leader>B <Plug>VmailMessageWindow_CopyToMailbox
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_CopyToMailbox :call <SID>focus_list_window()<cr>:call <SID>move_to_mailbox(1)<CR>

  if !hasmapto('<Plug>VmailMessageWindow_Update')
    nmap <buffer> <leader>u <Plug>VmailMessageWindow_Update
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_Update :call <SID>focus_list_window()<cr>:call <SID>update()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_SwitchMailBox')
    nmap <buffer> <leader>m <Plug>VmailMessageWindow_SwitchMailBox
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_SwitchMailBox :call <SID>focus_list_window()<cr>:call <SID>mailbox_window()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_SaveAttachment')
    nmap <buffer> <leader>A <Plug>VmailMessageWindow_SaveAttachment
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_SaveAttachment :call <SID>save_attachments()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_ToggleWindow')
    nmap <buffer> <Space> <Plug>VmailMessageWindow_ToggleWindow
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_ToggleWindow :call <SID>toggle_maximize_window()<cr>

  if !hasmapto('<Plug>VmailMessageWindow_AppendMessagesToFile')
    nmap <buffer> <leader>vp <Plug>VmailMessageWindow_AppendMessagesToFile
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_AppendMessagesToFile :call <SID>focus_list_window()<cr>:call <SID>append_messages_to_file()<CR>

  if !hasmapto('<Plug>VmailMessageWindow_Search')
    nmap <buffer> <leader>s <Plug>VmailMessageWindow_Search
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMessageWindow_Search :call <SID>focus_list_window()<cr>:call <SID>search_query()<cr>
endfunc

func! s:message_list_window_mappings()
  if !hasmapto('<Plug>VmailOpenMessage')
    nmap <buffer> <CR> <Plug>VmailOpenMessage
    nmap <buffer> <LeftMouse> <Plug>VmailOpenMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailOpenMessage :call <SID>show_message(0)<CR>

  if !hasmapto('<Plug>VmailPreviewMessage')
    nmap <buffer> l <Plug>VmailPreviewMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailPreviewMessage :call <SID>show_message(1)<CR>

  if !hasmapto('<Plug>VmailExit')
    nmap <buffer> <leader>q <Plug>VmailExit
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailExit :qall!<CR>

  if !hasmapto('<Plug>VmailToggleStar')
    nmap <buffer> <leader>* <Plug>VmailToggleStar
    xmap <buffer> <leader>* <Plug>VmailToggleStar
    nmap <buffer> <leader>8 <Plug>VmailToggleStar
    xmap <buffer> <leader>8 <Plug>VmailToggleStar
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailToggleStar :call <SID>toggle_star()<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailToggleStar :call <SID>toggle_star()<CR>

  if !hasmapto('<Plug>VmailToggleRead')
    nmap <buffer> <leader>U <Plug>VmailToggleRead
    xmap <buffer> <leader>U <Plug>VmailToggleRead
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailToggleRead :call <SID>toggle_flag('SEEN')<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailToggleRead :call <SID>toggle_flag('SEEN')<CR>

  if !hasmapto('<Plug>VmailDelete')
    nmap <buffer> <leader># <Plug>VmailDelete
    xmap <buffer> <leader># <Plug>VmailDelete
    nmap <buffer> <leader>3 <Plug>VmailDelete
    xmap <buffer> <leader>3 <Plug>VmailDelete
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailDelete :call <SID>delete_messages("Deleted")<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailDelete :call <SID>delete_messages("Deleted")<CR>

  if !hasmapto('<Plug>VmailMarkAsSpam')
    nmap <buffer> <leader>! <Plug>VmailMarkAsSpam
    xmap <buffer> <leader>! <Plug>VmailMarkAsSpam
    nmap <buffer> <leader>1 <Plug>VmailMarkAsSpam
    xmap <buffer> <leader>1 <Plug>VmailMarkAsSpam
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMarkAsSpam :call <SID>delete_messages("spam")<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailMarkAsSpam :call <SID>delete_messages("spam")<CR>

  if !hasmapto('<Plug>VmailArchiveMessage')
    nmap <buffer> <leader>e <Plug>VmailArchiveMessage
    xmap <buffer> <leader>e <Plug>VmailArchiveMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailArchiveMessage :call <SID>archive_messages()<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailArchiveMessage :call <SID>archive_messages()<CR>

  if !hasmapto('<Plug>VmailAppendMessagesToFile')
    nmap <buffer> <leader>vp <Plug>VmailAppendMessagesToFile
    xmap <buffer> <leader>vp <Plug>VmailAppendMessagesToFile
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailAppendMessagesToFile :call <SID>append_messages_to_file()<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailAppendMessagesToFile :call <SID>append_messages_to_file()<CR>

  if !hasmapto('<Plug>VmailUpdate')
    nmap <buffer> u <Plug>VmailUpdate
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailUpdate :call <SID>update()<CR>

  if !hasmapto('<Plug>VmailSearch')
    nmap <buffer> <leader>s <Plug>VmailSearch
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailSearch :call <SID>search_query()<CR>

  if !hasmapto('<Plug>VmailSwitchMailbox')
    nmap <buffer> <leader>m <Plug>VmailSwitchMailbox
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailSwitchMailbox :call <SID>mailbox_window()<CR>

  if !hasmapto('<Plug>VmailMoveToMailbox')
    nmap <buffer> <leader>b <Plug>VmailMoveToMailbox
    xmap <buffer> <leader>b <Plug>VmailMoveToMailbox
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailMoveToMailbox :call <SID>move_to_mailbox(0)<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailMoveToMailbox :call <SID>move_to_mailbox(0)<CR>

  if !hasmapto('<Plug>VmailCopyToMailbox')
    nmap <buffer> <leader>B <Plug>VmailCopyToMailbox
    xmap <buffer> <leader>B <Plug>VmailCopyToMailbox
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailCopyToMailbox :call <SID>move_to_mailbox(1)<CR>
  xnoremap <buffer> <unique> <script> <Plug>VmailCopyToMailbox :call <SID>move_to_mailbox(1)<CR>

  if !hasmapto('<Plug>VmailComposeNew')
    nmap <buffer> <leader>c <Plug>VmailComposeNew
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailComposeNew :call <SID>compose_message()<CR>

  if !hasmapto('<Plug>VmailComposeReply')
    nmap <buffer> <Leader>r <Plug>VmailComposeReply
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailComposeReply :call <SID>show_message(0)<CR>:call <SID>compose_reply(0)<CR>

  if !hasmapto('<Plug>VmailComposeReplyAll')
    nmap <buffer> <Leader>a <Plug>VmailComposeReplyAll
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailComposeReplyAll :call <SID>show_message(0)<CR>:call <SID>compose_reply(1)<CR>

  if !hasmapto('<Plug>VmailForward')
    nmap <buffer> <Leader>f <Plug>VmailForward
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailForward :call <SID>show_message(0)<CR>:call <SID>compose_forward()<CR>

  if !hasmapto('<Plug>VmailShowNextMessage')
    nmap <buffer> <C-j> <Plug>VmailShowNextMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailShowNextMessage :call <SID>show_next_message_in_list()<CR>

  if !hasmapto('<Plug>VmailShowPrevMessage')
    nmap <buffer> <C-k> <Plug>VmailShowPrevMessage
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailShowPrevMessage :call <SID>show_previous_message_in_list()<CR>

  if !hasmapto('<Plug>VmailToggleWindow')
    nmap <buffer> <Space> <Plug>VmailToggleWindow
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailToggleWindow :call <SID>toggle_maximize_window()<cr>

  autocmd CursorMoved <buffer> :redraw
  autocmd FileType vmail :call <SID>set_list_colors()
endfunc

func! s:compose_window_mappings()
  if !hasmapto('<Plug>VmailComposeWinClose')
    nmap <buffer> <leader>q <Plug>VmailComposeWinClose
  endif
  nnoremap <buffer> <unique> <script> <Plug>VmailComposeWinClose :call <SID>close_and_focus_list_window()<CR>
  setlocal ai
  command! -bar -nargs=1 -complete=file VMAttach call s:attach_file(<f-args>)
endfunc

func! s:global_mappings()
  " NOTE send_message is a global mapping, so user can load a saved
  " message from a file and send it
  nnoremap <silent> <leader>vs :call <SID>send_message()<CR>
  noremap <silent> <leader>o :call <SID>open_href(0)<cr> 
  noremap <silent> <leader>O :call <SID>open_href(1)<cr> 
  noremap <silent> <leader>? :call <SID>show_help()<cr>
  noremap <silent> <leader>qq :qal!<cr>
endfunc

func! s:set_list_colors()
  if !exists("g:syntax_on")
    return
  endif
  syn clear
  syn match vmailSizeCol /|\s\+\(< 1k\|\d*\(b\|k\|M\|G\)\)\s\+|/ contains=vmailSeperator contained
  syn match vmailFirstCol /^.\{-}|/ nextgroup=vmailDateCol
  syn match vmailFirstColAnswered /An/ contained containedin=vmailFirstCol
  syn match vmailFirstColForward /\$F/ contained containedin=vmailFirstCol
  syn match vmailFirstColNotJunk /No/ contained containedin=vmailFirstCol
  syn match vmailDateCol /\s\+... \d\d \(\(\d\d:\d\d..\)\|\(\d\{4}\)\)\s\+|/ nextgroup=vmailFromCol contains=vmailSeperator
  syn match vmailFromCol /\s.\{-}|\@=/ contained nextgroup=vmailFromSeperator
  syn match vmailFromColEmail /<[^ ]*/ contained containedin=vmailFromCol
  syn match vmailFromSeperator /|/ contained nextgroup=vmailSubject
  syn match vmailSubject /.*\s\+/ contained contains=vmailSizeCol
  syn match vmailSubjectRe /\cre:\|fwd\?:/ contained containedin=vmailSubject
  syn match vmailSeperator /|/ contained
  syn match vmailNewMessage /^\s*+.*/
  syn match vmailStarredMessage /^\s*\*.*/
  hi def link vmailFirstCol         Comment
  hi def link vmailDateCol          Statement
  hi def link vmailFromCol          Identifier
  hi def link vmailSizeCol          Constant
  hi def link vmailSeperator        Comment
  hi def link vmailFromSeperator    vmailSeperator
  hi def link vmailFromColEmail     Comment
  hi def link vmailSubjectRe        Type
  hi def link vmailFirstColSpec     Number
  hi def link vmailFirstColAnswered vmailFirstColSpec
  hi def link vmailFirstColForward  vmailFirstColSpec
  hi def link vmailFirstColNotJunk  vmailFirstColSpec
  hi def link vmailSpecialMsg       Special
  hi def link vmailNewMessage       vmailSpecialMsg
  hi def link vmailStarredMessage   vmailSpecialMsg
  syn match VmailBufferFlagged /^*.*/hs=s
  exec "hi def VmailBufferFlagged " . g:vmail_flagged_color
endfunc

"TODO see if using LocalLeader and maplocalleader makes more sense
let mapleader = ","

call s:global_mappings()

call s:create_list_window()

call s:create_message_window()

call s:focus_list_window() " to go list window

" send window width
call s:system_with_error_handling(s:set_window_width_command . winwidth(1))

autocmd bufreadpost *.txt call <SID>turn_into_compose_window()
normal G
call s:system_with_error_handling(s:select_mailbox_command . shellescape(s:mailbox))
call s:do_search()

