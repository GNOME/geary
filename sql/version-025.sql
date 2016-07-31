--
-- Add an index for MessageTable.reference_ids for finding related
-- forwarded messages.
--

CREATE INDEX MessageTableReferenceIdsIndex ON MessageTable(reference_ids);
