
create table if not exists messages (
  uid integer primary key,
  mailbox text,
  rfc822 text,
  size integer,
  flags text,
  subject text,
  sender text,
  recipients text,
  date text,
  plaintext text
);

