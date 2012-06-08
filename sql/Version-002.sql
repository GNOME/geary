
--
-- MessageAttachmentTable
--

CREATE TABLE MessageAttachmentTable (
    id INTEGER PRIMARY KEY,
    message_id INTEGER REFERENCES MessageTable ON DELETE CASCADE,
    filename TEXT,
    mime_type TEXT,
    filesize INTEGER
);

CREATE INDEX MessageAttachmentTableMessageIDIndex ON MessageAttachmentTable(message_id);

