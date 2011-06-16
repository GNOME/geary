
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
    
    subject TEXT,
    
    header TEXT,
    
    body TEXT
);

CREATE INDEX MessageTableMessageIDIndex ON MessageTable(message_id);

--
-- MessageLocationTable
--

CREATE TABLE MessageLocationTable (
    id INTEGER PRIMARY KEY,
    message_id INTEGER REFERENCES MessageTable ON DELETE CASCADE,
    folder_id INTEGER REFERENCES FolderTable ON DELETE CASCADE,
    ordering INTEGER
);

CREATE INDEX MessageLocationTableMessageIDIndex ON MessageLocationTable(message_id);
CREATE INDEX MessageLocationTableFolderIDIndex ON MessageLocationTable(folder_id);

--
-- IMAP-specific tables
--

--
-- ImapFolderPropertiesTable
--

CREATE TABLE ImapFolderPropertiesTable (
    id INTEGER PRIMARY KEY,
    folder_id INTEGER UNIQUE REFERENCES FolderTable ON DELETE CASCADE,
    uid_validity INTEGER,
    supports_children INTEGER,
    is_openable INTEGER
);

CREATE INDEX ImapFolderPropertiesTableFolderIDIndex ON ImapFolderPropertiesTable(folder_id);

--
-- ImapMessagePropertiesTable
--

CREATE TABLE ImapMessagePropertiesTable (
    id INTEGER PRIMARY KEY,
    message_id INTEGER UNIQUE REFERENCES MessageTable ON DELETE CASCADE,
    answered INTEGER,
    deleted INTEGER,
    draft INTEGER,
    flagged INTEGER,
    recent INTEGER,
    seen INTEGER,
    all_flags TEXT
);

CREATE INDEX ImapMessagePropertiesTableMessageIDIndex ON ImapMessagePropertiesTable(message_id);

