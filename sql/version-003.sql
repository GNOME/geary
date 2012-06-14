
--
-- SmtpOutboxTable
--

CREATE TABLE SmtpOutboxTable (
    id INTEGER PRIMARY KEY,
    ordering INTEGER,
    message TEXT
);

CREATE INDEX SmtpOutboxOrderingIndex ON SmtpOutboxTable(ordering ASC);

