--
-- Add the disposition column as a string so the client can decide which attachments to show.
-- Since all attachments up to this point have been non-inline, set it to that value (which
-- is defined in src/engine/api/geary-attachment.vala
--

ALTER TABLE MessageAttachmentTable ADD COLUMN disposition INTEGER;
UPDATE MessageAttachmentTable SET disposition=0;

