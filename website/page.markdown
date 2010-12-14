# vmail

vmail is a Vim interface to Gmail. Here are some screenshots:

<a href="images-vmail/1.png" rel="lightbox[screens]"><img src="images-vmail/1-small.png" /></a>
<a href="images-vmail/autocomplete.png" rel="lightbox[screens]"><img src="images-vmail/autocomplete-small.png" /></a>
<a href="images-vmail/attach.png" rel="lightbox[screens]"><img src="images-vmail/attach-small.png" /></a>

Why vmail? Because every minute you spend fumbling around in a web browser is a
minute you're not experiencing the Zen of using a real text editor and staying
close to the Unix command line. 
 
## Prerequisites

* a Gmail account
* a relatively recent version of Vim (vmail is developed against Vim 7.3)
* Ruby (vmail is developed using Ruby 1.9.2)
* RubyGems (if Ruby version is older than 1.9)
* the `lynx` text-only-mode web browser is required to view HTML mail parts in vmail

The current version of vmail assumes a Unix environment. I'll try to make later versions accommodate Windows.

## Installation

    gem install vmail

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
      Sent via vmail. http://danielchoi.com/software/vmail.html

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

To full-screen the message, press SPACE when the cursor is the message window.
To go back to the split view, press ENTER.

You can full-screen the list window by pressing SPACE while the cursor is in it.

vmail loads a certain number messages at a time, starting with the most recent.
If there are more messages that vmail hasn't loaded, you'll see a line at the
top of the list that looks something like this:

    > Load 100 more messages. 156 remaining.

Put the cursor on this line and press ENTER to load more of these messages.

Unread messages are marked with a `[+]` symbol.

## Starring, deleting, archiving

To star a message, put the cursor on it and type `,*` or alternatively `s`.
Starring a message copies it to the `starred` mailbox.  Starred messages are
marked with a `[*]` symbol and color-highlighted.

To delete a message, put the cursor on it and type `,#` or alternatively `,d`.
Deleting a message puts it in the `trash` mailbox. Deleting a message from the
`trash` mailbox deletes it permanently.

To archive a message, put the cursor on it and type `,e`.  Archiving a message
moves it to the `all` mailbox.

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


