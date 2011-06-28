drop table if exists version;
create table version (
  vmail_version text
);
create table if not exists messages (
  message_id text PRIMARY KEY,
  size integer,
  flags text,
  subject text,
  sender text,
  recipients text,
  date text,
  plaintext text,
  rfc822 text
);
create table if not exists labelings (
  label_id integer,
  message_id text,
  uid integer
);
create table if not exists labels (
  label_id integer PRIMARY KEY,
  name text UNIQUE
);

