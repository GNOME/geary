--
-- Rebuild corrupted message ids.
--

UPDATE MessageTable
SET message_id = '<' || message_id || '>'
WHERE (message_id NOT LIKE '<%') AND (message_id NOT LIKE ' <%');
