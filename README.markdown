# vmail

vmail is a Vim interface to Gmail. 

[screenshots]

Why vmail? Because some people are 1000 times more productive and happy in [Vim][vim]
than in any web browser or GUI program. 

[vim]:http://www.vim.org/

## Prerequisites

* a Gmail account
* a relatively recent version of Vim (vmail is developed against Vim 7.3)
* Ruby 1.9.0 or higher with SSL support compiled in (vmail is developed using Ruby 1.9.2)
* the `lynx` text-only-mode web browser is required to view HTML mail parts in vmail

To install Ruby 1.9.2, I recommend using the [RVM Version Manager][rvm].

[rvm]:http://rvm.beginrescueend.com

The current version of vmail assumes a Unix environment. 

Your Gmail account should be [IMAP-enabled][gmailimap]. 

[gmailimap]:http://mail.google.com/support/bin/answer.py?hl=en&answer=77695

If you want to use `elinks` to display HTML parts, [here are instructions][elinks-tip].

[elinks-tip]:https://github.com/danchoi/vmail/wiki/How-to-use-elinks-to-display-html-parts-of-emails

## Installation

    gem install vmail

Test your installation by typing `vmail -h`. You should see vmail's help.

On some systems you may run into a PATH issue, where the system can't find the
`vmail` command after installation. Please report this if you encounter this
problem, and mention what system you're using. You might want to try 

    sudo gem install vmail

to see if that puts `vmail` on your PATH.

vmail is evolving rapidly. To update to the latest version, simply run the
installation command again.

    gem install vmail

If you ever want to uninstall vmail from your system, just execute this command:

    gem uninstall vmail

... and all traces of vmail will removed, except the few files it creates
during execution (see below).

## Configuration file

To run vmail, create a yaml file called `.vmailrc` and save it either in the
current directory (the directory from which you launch vmail) or in your home
directory. 

The `.vmailrc` file should look something like this. Substitute your own values.

    username: dhchoi@gmail.com
    password: password
    name: Daniel Choi
    signature: |
      --
      Sent from vmail. http://danielchoi.com/software/vmail.html

This file should be formatted in [YAML syntax][1].

[1]:http://www.yaml.org/spec/1.2/spec.html

You can omit the password key-value pair if you'd rather not have the password
saved in the file. In that case, you'll prompted for the password each time you
start vmail.

You can also add an `always_cc:` key-value pair. This will pre-insert
whatever email address you specify in the `cc:` line of any email you
start composing in vmail.

If you want to configure vmail with multiple Gmail accounts, [here's how][multiaccount].

[multiaccount]:https://github.com/danchoi/vmail/wiki/How-can-i-quickly-switch-between-multiple-accounts%3F

If you are behind a firewall that blocks IMAP, see these [additional
configuration options][firewall] that you can use.

[firewall]:https://github.com/danchoi/vmail/wiki/How-to-use-vmail-behind-a-firewall-that-blocks-IMAP


## Contacts autocompletion

vmail uses Vim autocompletion to help you auto-complete email addresses.
To use this feature, generate a `vmail-contacts.txt` file in the current or
home directory. This is a simple list of your email contacts.
Invoking vmail with the `-g` option generates this file for you by
collecting all the recipients and cc's from your last 500 sent
emails. You can adjust this number by using `-g` with a number argument. 

After vmail generates this file for you, you can edit it however and whenever
you want, as long as there is one address per line.

## Starting vmail

Once you've created the configuration file and (optionally) the contacts file,
you can start vmail with

    vmail

This opens the vmail/Vim interface and shows you the last 100 messages in your
Gmail inbox.

You can have vmail show messages from any other mailbox (a.k.a. label) on
startup by passing in the mailbox name as an argument:

    vmail starred

You can also pass in search parameters after specifying the mailbox:

    vmail important from barackobama@whitehouse.gov

On startup, vmail loads 100 messages by default. You can increase or decrease
this number by passing in a number after the mailbox name:

    vmail inbox 700 subject unix

Passing in 0 as the number of messages returns all messages that match
the query:

    vmail inbox 0 subject unix # => returns all matching messages

## Viewing messages

The first screen vmail shows you is a list of messages. You can view a message
by moving the cursor line to it and pressing ENTER. This will split the screen
and show the message content in the bottom pane. Pressing ENTER will also move
the cursor to the message window. If you want to look at a message but keep the
cursor in the list window, type `l` (as in `l`ook) instead of ENTER.

To full-screen the message, press SPACE when the cursor is in the message
window.  You can also use the standard Vim key sequence `C-w C-o`.  To go back
to the split view, press SPACE or ENTER. (ENTER moves the cursor to the list
window.)

You can full-screen the list window by pressing SPACE while the cursor is in
it.  You can also use the standard Vim key sequence `C-w C-o`.  To go back to
the split view, press SPACE or ENTER. (ENTER opens a message and moves the
cursor to the message window.)

In the split view, you can jump between the two panes by just pressing ENTER
from either window.
You can also use the standard Vim key sequence `C-w C-w`.

You can use `<C-j>` or `,j` from either split window to show the next message.
You can use `<C-k>` or `,k` to show the previous message. 

vmail loads a certain number messages at a time, starting with the most recent.
If there are more messages that vmail hasn't loaded, you'll see a line at the
top of the list that looks something like this:

    > Load 100 more messages. 156 remaining.

Put the cursor on this line and press ENTER to load more of these messages.

Tip: To go straight to the top line and load more messages, type `gg<ENTER>`.

Unread messages are marked with a `+` symbol.

To view the raw RFC822 version of a message, type `,R` while viewing the message.

## Starring, deleting, archiving, marking spam

To star a message, put the cursor on it and type `,*`.  (Note that the comma
before the * is part of the key sequence.) Starring a message copies it to the
`starred` mailbox.  Starred messages are marked with a `*` symbol and
color-highlighted.

To delete a message, put the cursor on it and type `,#`.  Deleting a message
puts it in the `trash` mailbox. Deleting a message from the `trash` mailbox
deletes it permanently.

To archive a message, put the cursor on it and type `,e`.  Archiving a message
moves it to the `all` mailbox.

To mark a message spam, put the cursor on it and type `,!`. This moves the
message to to the `spam` mailbox.

You can use range selections in the message list when you star, delete, mark as
spam, or archive. Use `v` to start marking a range of lines (the vertical
position of the cursor doesn't matter).  Then type any of the above commands to
perform an action on all the messages you selected.

To save you keystrokes, vmail provides alternative key mappings for
`,*`, `,#`, and `,!`:

* star: `,*` &rarr; `,8`
* trash/delete: `,#` &rarr; `,3`
* mark spam: `,!` &rarr; `,1`

These save you from having to press the SHIFT key in each case. 

## Checking for new messages

To check for new messages in the current mailbox, press `u` in normal
mode if you're in the message list window or `,u` if you are in the
message window. Watch the status line.
 
## Switching mailboxes, moving messages, copying messages to another mailbox

To switch mailboxes, type `,m`. You'll see an autocomplete window appear at the top.
The standard Vim autocomplete keystrokes apply:

* `C-p` and `C-n` move you up and down the match list
* `C-e` closes the match list and lets you continue typing
* `C-u`: when the match list is active, cycles forward through the match list and what you've typed so far; when the match list is inactive, erases what you've typed.
* `C-x C-u` finds matches for what you've typed so far (when the match list window is closed)
* `C-y` selects the highlighted match without triggering ENTER
* ENTER selects the highlighted match from the match list 

Tip: start typing the first 1-3 characters of the mailbox name, then press
`C-n`, `C-u` or `C-p` until you highlight the right match, and finally press ENTER to
select.

To move a message to another mailbox, put the cursor on the message in the
message list, and type `,b`. You'll be prompted to select the target mailbox.

To copy a message to another mailbox, put the cursor on the message in the
message list, and type `,B`. You'll be prompted to select the target mailbox.

If you type in the name of a target mailbox that doesn't exist yet, vmail will
create it for you before performing a move or copy.

## Composing messages

To start writing a new a email message, type `,c`. That's a comma followed by
the character 'c'.

To reply to a message, type `,r`. 

To reply-all to a message, type `,a`. 

To forward a message, type `,f`.

All these commands open a message composition window. At the top, you will see 
mail headers like this:

    from: Daniel Choi <dhchoi@gmail.com>
    to:
    subject:

The `from:` field will be pre-filled from your `.vmailrc` configuration.
You're responsible for filling in the `to:` and the `subject:` fields.
You can add a `cc:` and `bcc:` field if you want.


When you fill in the recipient addresses, you can use Vim autocompletion
if you generated a `vmail-contacts.txt` file. Start typing a name or
email address, then press `C-x C-u` to invoke autocompletion. Select a
matching email address with `C-n`, `C-p`, or `C-u` and then press SPACE
or any other character (such as a `,`) to continue typing.

Make sure your email addresses are separated by commas and that they all
ultimately appear on the **same, unbroken line** for each field. Rejoin
the lines if breaks get inserted.

After you fill in the headers, write your message.  Make sure there is a
blank line between the headers and the body of your message.

When you're done writing, send the message by typing `,vs` in normal mode.

While you're composing a message in the composition window, you can save a
draft to a local file with the standard Vim `:w` command: 

    :w my_draft_filename.txt 

Make sure you append *.txt to the filename, or else vmail won't recognize it as
a potential email when you reload it.

Make sure you don't use `:wq` unless you mean to quit vmail immediately. After
you save the draft to a file, you can go back to the message list by typing `q`
in normal mode.

To resume writing the draft later, just type `:e my_draft_filename.txt` to load
the draft email into a buffer. (Use `:e!` if you're already in the message
composition window. You can also use `:sp` if you want to open the draft email file in a
split window, etc.) Resume editing. Send by typing `,vs`.

At any point, you can quit the composition window by typing `,q` in normal mode.

You can also use `vmailsend` from the command line to send a message that
you've composed with correct headers and saved to a file, like so:

    vmailsend < my_message.txt

vmailsend uses your `.vmailrc` configuration and assumes that you saved your
password in it. 

## Attachments

The current version of vmail can handle attachments to a certain extent.

When you're viewing a message with attachments, you'll see something like this
at the top of the message window:

    INBOX 2113 4 kb
    - image/png; name=canada.png
    - image/gif; name=arrow_right.gif
    ---------------------------------------
    from: Daniel Choi <dhchoi@gmail.com>
    date: Sun, Dec 12 08:39 AM -05:00 2010
    to: Daniel Choi <dhchoi@gmail.com>
    subject: attachment test

    see attached

To download these attachments to a local directory, type `,A`. You'll be
prompted for a directory path.  Then vmail will save all the attachments in the
message to this directory, creating the directory if necessary.

To send attachments, add something like this to your new message in the message
composition window:

    from: Daniel Choi <dhchoi@gmail.com>
    to: barackobama@whitehouse.gov
    subject: look at this!
    
    attach:
    - images/middle-east-map.png
    - images/policypaper.pdf
    - docs/
    
    I think you'll find this stuff interesting.
    

The `attach:` block is a YAML list. The items are paths (either relative to the
current directory or absolute) to the files you want to attach to your message.
Note that you can also specify a directory, in which case vmail attaches every
file it finds in that directory.

One thing vmail doesn't do yet is let you forward a message with all its
attachments intact.  This feature will be implemented in the near future. 

## Printing messages to a file

`,vp` from the message list prints (appends) the text content of all the selected
messages to a file.

## Opening hyperlinks and HTML parts in your web browser

When you're reading a message, `,o` opens the first hyperlink in the email
message on or after the cursor in your web browser. `,O` opens all the
hyperlinks in the message (probably in multiple browser tabs, depending on how
you set up your web browser). If you first select a range of text with
hyperlinks in it, both `,o` and `,O` will open all the hyperlinks in those
selected lines in your browser.

When you're reading a message with an html mail part, `,h` saves that part to a
local file (`part.html`) and opens it in your web browser.

By default, the vmail uses the command `open` to launch your web browser. In OS X,
this opens URLs and HTML files in the default web browser.  You can change the
browser vmail invokes by setting the VMAIL_BROWSER environmental variable
before you start vmail, e.g.:

    export VMAIL_BROWSER='elinks'

Also, if your Vim has `netrw` (`:help netrw`), you can open a hyperlink
directly in same Vim window by putting the cursor at the beginning of a
hyperlink and typing `gf`, or `C-w f` if you want to open the webpage in a
split window. 

## Search queries

vmail can generate a message list by performing an IMAP search on the current mailbox.
From the message list window, type `,s`. This will prompt you for a search query. 
The search query is an optional number specifying the number of messages to return, 
followed by a valid IMAP search query.

Here are some example search queries.

    # the default 
    100 all  

    # all messages from thematrix.com domain
    from thematrix.com  

    # all messages from this person
    from barackobama@whitehouse.gov  

    # you can also omit the host part of the email address
    from barackobama

    # you can also search by the full name, first name, or last name associated
    # with an email; use double quotes to enclose multiple words 
    cc "David Fisher"

    # subject field search; use double quotes to enclose multiple words
    subject "unix philosophy"  

    # message body search; use double quotes to enclose multiple words
    body "unix philosophy"  

    # example of date range and multiple conditions
    before 30-nov-2010 since 1-nov-2010 from prx.org  

    # search for all messages since 1-nov-2010 larger than 10k
    # (note that queries with size conditions seem to take longer to return)
    since 1-nov-2010 larger 10000

Tip: When you're entering your search query, `<C-u>` clears the query line.

Power-Tip: When you're at the search query prompt, `C-p` and `C-n` let you
navigate the search query history. `<C-f>` opens a mini-editor that contains
the current query plus a history of previous vmail search queries. You can edit
any line in this mini-editor and press ENTER to perform the query on that line.

## Command-line mode and batch processing

You can invoke vmail in non-interactive command-line mode. This is very
useful for batch processing and for using vmail in Unix pipelines and
automated scripts.

If you redirect vmail's output from STDOUT to a file or a program, vmail will
output the message list resulting from a search query to a file.

    vmail inbox 100 from monit > message-list.txt 

You can open this file in any text editor to make sure that the search
query produced the expected result. Then you can perform the following
batch operations on the message list:

    # deletes all the messages in the message list
    vmail rm < message-list.txt

    # marks all the messages in the message list as spam
    vmail spam < message-list.txt

    # moves all the messages in the message list to the 'monit' mailbox
    vmail mv monit < message-list.txt

    # copies all the messages in the message list to the 'monit' mailbox
    vmail cp monit < message-list.txt

    # appends the text content of all the messages in the message list to messages.txt
    vmail print messages.txt < message-list.txt

Non-interactive mode assumes that `.vmailrc` contains your Gmail password.

## Getting help

Typing `,?` will open this webpage in a browser.

## Using vmail with MacVim

To use MacVim as your vmail Vim engine, `export VMAIL_VIM=mvim` before starting
vmail or put this command in your `~/.bash_profile`.

Note that when vmail uses MacVim, the terminal window in which you invoke vmail
will show vmail's logging output while MacVim is running. To quit vmail in
MacVim mode, first quit the MacVim window running vmail, and then press CTRL-c
in the original terminal window to stop the vmail process.

## vmail file byproducts

vmail generates a few files in the current directory when it is running: 

* `vmailbuffer` holds the message list. This file should get deleted automatically when vmail quits.

* `current_message.txt` holds the current message being shown. Not deleted on quit.

* `sent-messages.txt` will contain copies of any messages you send from vmail

* `part.html` is created if you open an HTML mail part from vmail. 

Finally, vmail logs output to a `vmail.log` file which it creates in the
current directory. You can tail this file in a separate terminal window to see
what's going on behind the scenes as you use vmail.

## Is my Gmail password secure?

In short, yes. vmail uses TLS ([Transport Layer Security][tls]) to perform IMAP
and SMTP authentication. So vmail transmits your password securely over the
network.

[tls]:http://en.wikipedia.org/wiki/Transport_Layer_Security

You can also be sure that the vmail code doesn't do anything nefarious with
your Gmail password because vmail is open source. Anyone can inspect the source
code of the copy of vmail that runs on your computer and inspect the latest
vmail code at the [github repository][github] and at [rubygems.org][rubygems] (where the
vmail gem is downloaded from). 

[github]:https://github.com/danchoi/vmail
[rubygems]:https://rubygems.org/gems/vmail


## Quitting Vmail

* `,qq` will quit Vmail from any window. It's equivalent to `:qall!`

## Redrawing the screen

If you run commands in very fast succession, the screen may get a little messed
up. In that case, just force a redraw of the Vim screen with `C-l`.

## Customizing colors

By default, vmail highlights starred messages in bold green against a black
background. You can customize this setting by adding a line to your `~/.vimrc`
(not `.vmailrc`) file like so:
    
    let g:vmail_flagged_color = "ctermfg=yellow ctermbg=black cterm=bold"

Type `:help highlight-args` in Vim for more details.

## Bug reports, feature requests, user community

Please file bug reports and feature requests in the [vmail github issue tracker][tracker].

You can also vote up existing feature requests on the issue tracker.

vmail is very young and in beta, so there are bound to be bugs and issues.
But in a few weeks, with your help, vmail will become stable.

[tracker]:https://github.com/danchoi/vmail/issues

You can also join and comment in the [vmail-users Google Group][group].

[group]:https://groups.google.com/group/vmail-users?hl=en

If you have any tips or troubleshooting advice you want to share with other
vmail users, please add them to the [vmail wiki][wiki].

[wiki]:https://github.com/danchoi/vmail/wiki

## How to contact the developer

My name is Daniel Choi. I am based in Cambridge, Massachusetts, USA, and you
can email me at dhchoi@gmail.com.  You can [follow me on Twitter][twitter] too.
A big shout out goes to my funny, smart, and supportive fellow hacker alums of
[Betahouse][betahouse].

[betahouse]:http://betahouse.org/

[twitter]:http://twitter.com/#!/danchoi

