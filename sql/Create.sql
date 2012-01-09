
--
-- FolderTable
--

CREATE TABLE FolderTable (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INTEGER REFERENCES FolderTable ON DELETE RESTRICT
);

CREATE INDEX FolderTableNameIndex ON FolderTable(name);
CREATE INDEX FolderTableParentIndex ON FolderTable(parent_id);

--
-- MessageTable
--

CREATE TABLE MessageTable (
    id INTEGER PRIMARY KEY,
    fields INTEGER,
    
    date_field TEXT,
    date_time_t INTEGER,
    
    from_field TEXT,
    sender TEXT,
    reply_to TEXT,
    
    to_field TEXT,
    cc TEXT,
    bcc TEXT,
    
    message_id TEXT,
    in_reply_to TEXT,
    reference_ids TEXT,
    
    subject TEXT,
    
    header TEXT,
    
    body TEXT,
    
    preview TEXT
);

CREATE INDEX MessageTableMessageIDIndex ON MessageTable(message_id);

--
-- MessageLocationTable
--

CREATE TABLE MessageLocationTable (
    id INTEGER PRIMARY KEY,
    message_id INTEGER REFERENCES MessageTable ON DELETE CASCADE,
    folder_id INTEGER REFERENCES FolderTable ON DELETE CASCADE,
    ordering INTEGER,
    remove_marker INTEGER DEFAULT 0
);

CREATE INDEX MessageLocationTableMessageIDIndex ON MessageLocationTable(message_id);
CREATE INDEX MessageLocationTableFolderIDIndex ON MessageLocationTable(folder_id);
CREATE INDEX MessageLocationTableOrderingIndex ON MessageLocationTable(ordering ASC);

--
-- IMAP-specific tables
--

--
-- ImapFolderPropertiesTable
--

CREATE TABLE ImapFolderPropertiesTable (
    id INTEGER PRIMARY KEY,
    folder_id INTEGER UNIQUE REFERENCES FolderTable ON DELETE CASCADE,
    last_seen_total INTEGER,
    uid_validity INTEGER,
    uid_next INTEGER,
    attributes TEXT
);

CREATE INDEX ImapFolderPropertiesTableFolderIDIndex ON ImapFolderPropertiesTable(folder_id);

--
-- ImapMessagePropertiesTable
--

CREATE TABLE ImapMessagePropertiesTable (
    id INTEGER PRIMARY KEY,
    message_id INTEGER UNIQUE REFERENCES MessageTable ON DELETE CASCADE,
    flags TEXT,
    internaldate TEXT,
    rfc822_size INTEGER
);

CREATE INDEX ImapMessagePropertiesTableMessageIDIndex ON ImapMessagePropertiesTable(message_id);

