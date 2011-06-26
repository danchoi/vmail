create table if not exists folders (
  name text
);

create table if not exists messages (
  uid integer primary key,
  rfc822 text,
  size integer,
  flags text,
  subject text,
  sender text,
  date text,
  plaintext text
);

