#!/bin/bash
ruby lib/client.rb select_mailbox "$1"
shift
ruby lib/client.rb search $@ > out
vim -S viewer.vim out

