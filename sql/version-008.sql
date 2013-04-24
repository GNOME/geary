--
-- Index the in_reply_to column, since we're searching on it now.
--

CREATE INDEX MessageTableInReplyToIndex ON MessageTable(in_reply_to);
