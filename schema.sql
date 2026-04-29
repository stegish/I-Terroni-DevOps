drop table if exists user;
create table user (
  user_id integer primary key autoincrement,
  username string not null,
  email string not null,
  pw_hash string not null
);

drop table if exists follower;
create table follower (
  who_id integer,
  whom_id integer
);
create index idx_follower_who_id on follower(who_id);
create index idx_follower_whom_id on follower(whom_id);

drop table if exists message;
create table message (
  message_id integer primary key autoincrement,
  author_id integer not null,
  text string not null,
  pub_date integer,
  flagged integer
);
create index idx_message_pub_date on message(pub_date desc);
create index idx_message_flagged on message(flagged);
create index idx_message_author_id on message(author_id);
