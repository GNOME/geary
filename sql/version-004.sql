
--
-- Migrate ImapFolderPropertiesTable into FolderTable
--

ALTER TABLE FolderTable ADD COLUMN last_seen_total INTEGER;
ALTER TABLE FolderTable ADD COLUMN uid_validity INTEGER;
ALTER TABLE FolderTable ADD COLUMN uid_next INTEGER;
ALTER TABLE FolderTable ADD COLUMN attributes TEXT;

UPDATE FolderTable
    SET
        last_seen_total = (SELECT ImapFolderPropertiesTable.last_seen_total FROM ImapFolderPropertiesTable WHERE ImapFolderPropertiesTable.folder_id = FolderTable.id),
        uid_validity = (SELECT ImapFolderPropertiesTable.uid_validity FROM ImapFolderPropertiesTable WHERE ImapFolderPropertiesTable.folder_id = FolderTable.id),
        uid_next = (SELECT ImapFolderPropertiesTable.uid_next FROM ImapFolderPropertiesTable WHERE ImapFolderPropertiesTable.folder_id = FolderTable.id),
        attributes = (SELECT ImapFolderPropertiesTable.attributes FROM ImapFolderPropertiesTable WHERE ImapFolderPropertiesTable.folder_id = FolderTable.id)
    WHERE EXISTS 
        (SELECT * FROM ImapFolderPropertiesTable WHERE ImapFolderPropertiesTable.folder_id = FolderTable.id);

DROP TABLE ImapFolderPropertiesTable;

--
-- Migrate ImapMessagePropertiesTable into MessageTable
--

ALTER TABLE MessageTable ADD COLUMN flags TEXT;
ALTER TABLE MessageTable ADD COLUMN internaldate TEXT;
ALTER TABLE MessageTable ADD COLUMN rfc822_size INTEGER;

CREATE INDEX MessageTableInternalDateIndex ON MessageTable(internaldate);
CREATE INDEX MessageTableRfc822SizeIndex ON MessageTable(rfc822_size);

UPDATE MessageTable
    SET
        flags = (SELECT ImapMessagePropertiesTable.flags FROM ImapMessagePropertiesTable WHERE ImapMessagePropertiesTable.message_id = MessageTable.id),
        internaldate = (SELECT ImapMessagePropertiesTable.internaldate FROM ImapMessagePropertiesTable WHERE ImapMessagePropertiesTable.message_id = MessageTable.id),
        rfc822_size = (SELECT ImapMessagePropertiesTable.rfc822_size FROM ImapMessagePropertiesTable WHERE ImapMessagePropertiesTable.message_id = MessageTable.ID)
    WHERE EXISTS
        (SELECT * FROM ImapMessagePropertiesTable WHERE ImapMessagePropertiesTable.message_id = MessageTable.id);

DROP TABLE ImapMessagePropertiesTable;

