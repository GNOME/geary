--
-- Add the internaldate column as a time_t value so we can sort on it.
--

ALTER TABLE MessageTable ADD COLUMN internaldate_time_t INTEGER;

CREATE INDEX MessageTableInternalDateTimeTIndex ON MessageTable(internaldate_time_t);
