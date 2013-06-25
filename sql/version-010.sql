--
-- Add unread count column to the FolderTable
--

ALTER TABLE FolderTable ADD COLUMN unread_count INTEGER DEFAULT 0;
