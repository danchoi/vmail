#vmail

vmail is a Vim interface to Gmail. Here are some screenshots:

<a href="images-vmail/1.png" rel="lightbox[screens]"><img src="images-vmail/1-small.png" /></a>
<a href="images-vmail/autocomplete.png" rel="lightbox[screens]"><img src="images-vmail/autocomplete-small.png" /></a>
<a href="images-vmail/attach.png" rel="lightbox[screens]"><img src="images-vmail/attach-small.png" /></a>

Why vmail? Because every minute you spend fumbling around in a web browser is a
minute you're not experiencing the Zen of using a real text editor and staying
close to the Unix command line.
 
##Prerequisites

* a Gmail account
* a relatively recent version of Vim (vmail is developed against Vim 7.3)
* Ruby (vmail is developed using Ruby 1.9.2)
* RubyGems (if Ruby version is older than 1.9)
* the `lynx` text-only-mode web browser is required to view HTML mail parts in vmail

The current version of vmail assumes a Unix environment. I'll try to make later versions accommodate Windows.

##Installation

    gem install vmail

##Configuration File

To run vmail, create a yaml file called .vmailrc and save it either in the
current directory (the directory from which you launch vmail) or in your home
directory. 

This file should look something like this. Substitute your own values.

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

#Contacts Autocompletion

vmail uses vim autocompletion to help you auto-complete email addresses.
To use this feature, generate a vim-contacts.txt file in the current or
home directory. This is a simple list of your email contacts.
Invoking vmail with the -g option generates this file for you by
collecting all the recipients and cc's from your last 500 sent
emails. You can adjust this number by using -g with a number argument. 



