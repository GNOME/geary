--
-- Database upgrade to repopulate attachments.  Bug #713830 revealed that
-- non-text and non-image files with no Content-Disposition were being dropped.
-- Also add Content-ID to database so attachments in RCF822 messages can be paired
-- to extracted attachments on filesystem.
--

ALTER TABLE MessageAttachmentTable ADD COLUMN content_id TEXT DEFAULT NULL;
ALTER TABLE MessageAttachmentTable ADD COLUMN description TEXT DEFAULT NULL;

