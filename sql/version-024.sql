--
-- Add the DeleteAttachmentFile table, which allows for attachment files to be deleted (garbage
-- collected) after all references to them have been removed from the database without worrying
-- about deleting them first and the database transaction failing.
--
-- Also add GarbageCollectionTable, a single-row table holding various information about when
-- GC has occurred and when it should occur next.
--

CREATE TABLE DeleteAttachmentFileTable (
    id INTEGER PRIMARY KEY,
    filename TEXT NOT NULL
);

CREATE TABLE GarbageCollectionTable (
    id INTEGER PRIMARY KEY,
    last_reap_time_t INTEGER DEFAULT NULL,
    last_vacuum_time_t INTEGER DEFAULT NULL,
    reaped_messages_since_last_vacuum INTEGER DEFAULT 0
);

-- Insert a single row with a well-known rowid and default values, this will be the row used
-- by the ImapDB.GC class.
INSERT INTO GarbageCollectionTable (id) VALUES (0);

