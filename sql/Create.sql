
CREATE TABLE FolderTable (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    supports_children INTEGER,
    is_openable INTEGER,
    parent_id INTEGER
);

CREATE INDEX FolderTableNameIndex ON FolderTable (name);
CREATE INDEX FolderTableParentIndex ON FolderTable (parent_id);

