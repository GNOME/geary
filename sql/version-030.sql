--
-- Convert full-text search from FTS3/4 to FTS5
--

DROP TABLE IF EXISTS MessageSearchTable;

CREATE VIRTUAL TABLE MessageSearchTable USING fts5(
    body,
    attachments,
    subject,
    "from",
    receivers,
    cc,
    bcc,
    flags,

    tokenize="unicode61 remove_diacritics 2",
    prefix="2,4,6,8,10"
)
