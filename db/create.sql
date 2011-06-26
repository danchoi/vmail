create table if folders (
  name text
);

create table if not exists messages (
  uid integer,
  rfc822 text,
  subject text,
  plaintext text,
  date text,

);
