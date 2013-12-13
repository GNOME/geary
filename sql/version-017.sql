--
-- Create the persistent replay queue.  This allows for operations on the server to be queued
-- locally and replayed (executed) in order when the connection is available.
--

CREATE TABLE ReplayQueueTable (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_id INTEGER REFERENCES FolderTable ON DELETE CASCADE
    activation_record TEXT
);

CREATE INDEX ReplayQueueTableFolderIndex ON ReplayQueueTable(folder_id);

