# vmail

vmail is a Vim interface to Gmail. Here are some screenshots:

Why vmail? Because some people love using Vim 1000 times more than using
a web browser or a GUI mail program. 

 
## Prerequisites

* a Gmail account
* a relatively recent version of Vim (vmail is developed against Vim 7.3)
* Ruby (vmail is developed using Ruby 1.9.2)
* RubyGems (if Ruby version is older than 1.9)
* the `lynx` text-only-mode web browser is required to view HTML mail parts in vmail

The current version of vmail assumes a Unix environment. I'll try to make later versions accommodate Windows.

## Installation

    gem install vmail

Test your installation by typing `vmail -h`. You should see vmail's help.

On some systems you may run into a PATH issue, where the system can't find the
`vmail` command after installation. Please report this if you encounter this
problem, and mention what system you're using. You might want to try 

    sudo gem install vmail

to see if that puts `vmail` on your PATH.

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

## Contacts autocompletion

vmail uses vim autocompletion to help you auto-complete email addresses.
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

This opens the vmail/vim interface and shows you the last 100 messages in your
Gmail inbox.

You can have vmail show messages from any other mailbox (a.k.a. label) on
startup by passing in the mailbox name as an argument:

    vmail starred

You can also pass in search parameters:

    vmail important from barackobama@whitehouse.gov

On startup, vmail loads 100 messages by default. You can increase or decrease
this number by passing in a number after the mailbox name:

    vmail inbox 700 subject unix

## Viewing messages

The first screen vmail shows you is a list of messages. You can view a message
by moving the cursor line to it and pressing ENTER. This will split the screen
and show the message content in the bottom pane.

To full-screen the message, press SPACE when the cursor is in the message window.
To go back to the split view, press ENTER.

You can full-screen the list window by pressing SPACE while the cursor is in it.

In the split view, you can jump between the two panes by just pressing ENTER
from either window.

You can also use `<C-p>` and `<C-n>` from either window to show the previous or
next message.

vmail loads a certain number messages at a time, starting with the most recent.
If there are more messages that vmail hasn't loaded, you'll see a line at the
top of the list that looks something like this:

    > Load 100 more messages. 156 remaining.

Put the cursor on this line and press ENTER to load more of these messages.

Unread messages are marked with a `[+]` symbol.

To view the raw RFC822 version of a message, type `,R` while viewing the message.

## Starring, deleting, archiving, marking spam

To star a message, put the cursor on it and type `,*` or alternatively `s`.
(Note that the comma before the * is part of the key sequence.) Starring a
message copies it to the `starred` mailbox.  Starred messages are marked with a
`[*]` symbol and color-highlighted.

To delete a message, put the cursor on it and type `,#` or alternatively `,d`.
Deleting a message puts it in the `trash` mailbox. Deleting a message from the
`trash` mailbox deletes it permanently.

To archive a message, put the cursor on it and type `,e`.  Archiving a message
moves it to the `all` mailbox.

To mark a message spam, put the cursor on it and type `,!`. This moves the
message to to the `spam` mailbox.

You can use range selections in the message list when you star, delete, mark as
spam, or archive. Use `<C-v>` to start marking a range of lines (the vertical
position of the cursor doesn't matter).  Then type any of the above commands to
perform an action on all the messages you selected.

## Checking for new messages

To check for new messages in the current mailbox, press `u` in normal mode and
watch the status line.
 
## Switching mailboxes, moving messages, copying messages to another mailbox

To switch mailboxes, type `,m`. You'll see an autocomplete window appear at the top.
The standard vim autocomplete keystrokes apply:

* `C-p` and `C-n` move you up and down the match list
* `C-e` closes the match list and lets you continue typing
* `C-u`: when the match list is active, cycles forward through the match list and what you've typed so far; when the match list is inactive, erases what you've typed.
* `C-x C-u` finds matches for what you've typed so far (when the match list window is closed)
* `C-y` selects the highlighted match without triggering ENTER
* ENTER selects the highlighted match from the match list 

Tip: start typing the first 1-3 characters of the mailbox name, then press
`C-u` or `C-p` until you highlight the right match, and finally press ENTER to
select.

To move a message to another mailbox, put the cursor on the message in the
message list, and type `,b`. You'll be prompted to select the target mailbox.

To copy a message to another mailbox, put the cursor on the message in the
message list, and type `,B`. You'll be prompted to select the target mailbox.

## Composing messages

To start writing a new a email message, type `,c`. That's a comma followed by
the character 'c'.

To reply to a message, type `,r`. 

To reply-all to a message, type `,a`. 

To forward a message, type `,f`.

All these command open a message composition window. At the top, you will see 
mail headers like this:

    from: Daniel Choi <dhchoi@gmail.com>
    to:
    subject:

The `from:` field will be pre-filled from your `.vmailrc` configuration.
You're responsible for filling in the `to:` and the `subject:` fields.
You can add a `cc:` and `bcc:` field if you want.


When you fill in the recipient addresses, you can use vim autocompletion if you
generated a `vmail-contacts.txt` file. Start typing a name or email address,
then press `C-x C-u` to invoke autocompletion.

Tip: Use `C-y` instead of ENTER to select a match. This will prevent you from
creating a blank line in the middle of the email headers.

Make sure your email addresses are separated by commas and that they all
ultimately appear on the **same, unbroken line** for each field. Vim will
probably break long lines automatically as you type them, so for now (pending a
future enhancement), you'll have to rejoin the lines if breaks get inserted.

After you fill in the headers, write your message.  Make sure there is a
blank line between the headers and the body of your message.

When you're done writing, send the message by typing `,vs` in normal mode.

While you're composing a message in the composition window, you can save a
draft to a local file with the standard vim `:w` command: 

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

At any point, you can quit the composition window by typing `q` in normal mode.

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
    

The `attach:` block is a YAML list. The items are paths (either relative or
absolute) to the files you want to attach to your message. Note that you can
also specify a directory, in which case vmail attaches every file it finds in
that directory.

One thing vmail doesn't do yet is let you forward a message with all its
attachments intact.  This feature will be implemented in the near future. 

## Printing messages to a file

`,vp` from the message list prints (appends) the text content of all the selected
messages to a file.

## Invoking your web browser 

When you're reading a message, `,o` opens the first hyperlink in the document
on or after the cursor in your normal web browser.

When you're reading a message with an html mail part, `,h` saves that part to a
local file (`vmail-htmlpart.html`) and opens it in your normal web browser.

By default, the command vmail uses to open your web browser is `open`. In OS X,
this opens URLs and HTML files in the default web browser.  You can change the
browser vmail invokes by setting the VMAIL_BROWSER environmental variable
before you start vmail, e.g.:

    export VMAIL_BROWSER='elinks'

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

    # subject field search; use double quotes to enclose multiple words
    subject "unix philosophy"  

    # example of date range and multiple conditions
    before 30-Nov-2010 since 1-Nov-2010 from prx.org  

Tip: When you're entering your search query, `<C-u>` clears the query line.

Power-Tip: When you're at the search query prompt, `<C-f>` opens a mini-editor
that contains the current query plus a history of previous vmail search
queries. You can edit any line in this mini-editor and press ENTER to perform
the query on that line.

## Using vmail with MacVim

vmail uses standard Vim by default, but vmail also works with MacVim, but not
perfectly. In particular, there seems to be a bug in MacVim that prevents
vmail's status line activity messages from appearing properly. Nonetheless,
most of vmail is functional in MacVim.

To use MacVim as your vmail Vim engine, `export VMAIL_VIM=mvim` before starting
vmail.

Note that when vmail uses MacVim, the terminal window in which you invoke vmail
will show vmail's logging output while MacVim is running. To quit vmail in
MacVim mode, you will have to press CTRL-c in this window to stop the vmail
process in after quitting the MacVim app.

## vmail file byproducts

vmail generates a few file byproducts when it is running. It generates a
temporary `vmailbuffer` file in the current directory to hold the message
list. This should get deleted automatically when vmail quits.

vmail also creates a `vmail-htmlpart.html` file in the current directory if you
open an HTML mail part from vmail. 

Finally, vmail logs output to a `vmail.log` file which it creates in the
current directory. You can tail this file in a separate terminal window to see
what's going on behind the scenes as you use vmail.

## Is my gmail password secure?

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

## Bug reports, feature requests

Please file bug reports and feature requests in the [vmail github issue tracker][tracker].

vmail is very young and in beta, so there are bound to be bugs and issues.
But in a few weeks, with your help, vmail will become stable.

[tracker]:https://github.com/danchoi/vmail/issues

## How to contact the developer

My name is Daniel Choi. I am based in Cambridge, MA, and you can email me at dhchoi@gmail.com.

