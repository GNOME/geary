--
-- Database upgrade to add FTS tokenize virtual table, which allows for querying the tokenizer
-- directly for stemmed words, and dropping the stemmed FTS table for an unstemmed one.  We now
-- use the stemmer manually to generate search queries.
--

DROP TABLE MessageSearchTable;

CREATE VIRTUAL TABLE MessageSearchTable USING fts4(
    body,
    attachment,
    subject,
    from_field,
    receivers,
    cc,
    bcc,
    
    tokenize=simple,
    prefix="2,4,6,8,10"
);

