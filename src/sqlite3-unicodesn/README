SQLite3-unicodesn
==============

SQLite "unicode" full-text-search tokenizer with Snowball stemming

Installation
============

   $ git clone git://github.com/littlesavage/sqlite3-unicodesn.git
   $ cd sqlite3-unicodesn
   $ make
   $ su
   # make install

Usage
======

    $ sqlite3
    sqlite> .load unicodesn.sqlext
    sqlite> CREATE VIRTUAL TABLE fts USING fts3(text, tokenize=unicodesn "stemmer=russian");
    sqlite> INSERT INTO fts VALUES ("Пионэры! Идите в жопу!");
    sqlite> SELECT * FROM fts WHERE text MATCH 'Жопа';
    Пионэры! Идите в жопу!

License
=======

Snowball files and stemmers are covered by the BSD license.

SQLite is in the Public Domain.

SQLite3-unicodesn code is in the Public Domain.

