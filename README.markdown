# vmail

This project provides a Vim interface to Gmail.

This is an alpha version. To run it, you need vim or macvim. 

You also need ruby (1.9.2 recommended but not required) and rubygems.

Once you have those prerequisites, you can install vmail with `gem install
vmail`.

To use this alpha version, you need to put a gmail.yml file in your home
directory.

The format of the yaml file is as follows:

    username: dhchoi@gmail.com
    password: mypassword
    name: Daniel Choi
    signature: |
      --
      Sent via vmail. http://danielchoi.com

Start the program by typing `vmail` on your command line. If you want to use the Macvim 
version, type `mvmail`.

There is no real documentation as of yet, but here are the raw vimscript mappings


## From Message List Window:

    inoremap <silent> <buffer> <esc> <Esc>:q<cr>
    inoremap <silent> <buffer> <esc> <Esc>:q<cr>
    noremap <silent> <buffer> <cr> :call <SID>show_message()<CR>
    noremap <silent> <buffer> q :qal!<cr>
    noremap <silent> <buffer> s :call <SID>toggle_star()<CR>
    noremap <silent> <buffer> <leader>d :call <SID>delete_messages("Deleted")<CR>
    noremap <silent> <buffer> <leader>! :call <SID>delete_messages("[Gmail]/Spam")<CR>
    noremap <silent> <buffer> u :call <SID>update()<CR>
    noremap <silent> <buffer> <Leader>s :call <SID>search_window()<CR>
    noremap <silent> <buffer> <Leader>m :call <SID>mailbox_window()<CR>
    noremap <silent> <buffer> <Leader>v :call <SID>move_to_mailbox()<CR>
    noremap <silent> <buffer> <Leader>c :call <SID>compose_message()<CR>
    noremap <silent> <buffer> <Leader>r :call <SID>show_message()<cr>:call <SID>compose_reply(0)<CR>
    " reply all
    noremap <silent> <buffer> <Leader>a :call <SID>show_message()<cr>:call <SID>compose_reply(1)<CR>


## From Message Window:

    noremap <silent> <buffer> <cr> :call <SID>focus_list_window()<CR> 
    noremap <silent> <buffer> <Leader>q :call <SID>focus_list_window()<CR> 
    nnoremap <silent> <buffer> q :close<cr>
    noremap <silent> <buffer> q <Leader>q
    noremap <silent> <buffer> <Leader>r :call <SID>compose_reply(0)<CR>
    noremap <silent> <buffer> <Leader>a :call <SID>compose_reply(1)<CR>
    noremap <silent> <buffer> <Leader>R :call <SID>show_raw()<cr>
    noremap <silent> <buffer> <Leader>f :call <SID>compose_forward()<CR><cr>
    noremap <silent> <buffer> <leader>j :call <SID>show_next_message()<CR> 
    noremap <silent> <buffer> <leader>k :call <SID>show_previous_message()<CR> 
    noremap <silent> <buffer> <Leader>c :call <SID>compose_message()<CR>
    noremap <silent> <buffer> <Leader>h :call <SID>open_html_part()<CR><cr>
    nnoremap <silent> <buffer> <leader>d  :call <SID>focus_list_window()<cr>:call <SID>delete_messages("Deleted")<cr>
    nnoremap <silent> <buffer> s  :call <SID>focus_list_window()<cr>:call <SID>toggle_star()<cr>
    nnoremap <silent> <buffer> <Leader>m :call <SID>focus_list_window()<cr>:call <SID>mailbox_window()<CR>
    nnoremap <silent> <buffer> <Leader>A :call <SID>save_attachments()<cr>


## From Message Compose Window

    noremap <silent> <buffer> <Leader>d :call <SID>deliver_message()<CR>
    nnoremap <silent> <buffer> q :call <SID>cancel_compose()<cr>
    nnoremap <silent> <buffer> <leader>q :call <SID>cancel_compose()<cr>
    nnoremap <silent> <buffer> <Leader>s :call <SID>save_draft()<CR>

Other:

    nnoremap <silent> <buffer> <Space> :call <SID>toggle_fullscreen()<cr>



## Open Source License

The source code for vmail is governed by the MIT License, which reads as
follows:

    Copyright (c) 2010 Daniel Choi

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to
    deal in the Software without restriction, including without limitation the
    rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
    sell copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
    IN THE SOFTWARE.

