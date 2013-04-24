--
-- Gmail has a serious bug: its STATUS command returns a message count that includes chat messages,
-- but the SELECT/EXAMINE result codes do not.  That means its difficult to confirm changes to a
-- mailbox without SELECTing it each pass.  This schema modification allows for Geary to store both
-- the SELECT/EXAMINE count and STATUS count in the database for comparison.
--

ALTER TABLE FolderTable ADD COLUMN last_seen_status_total;

