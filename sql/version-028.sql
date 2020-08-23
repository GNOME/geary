--
-- Rebuild corrupted message ids, again
--

UPDATE MessageTable
SET message_id = trim(trim(message_id), '\n');
