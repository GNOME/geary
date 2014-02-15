--
-- Nuke the internaldate_time_t column, because it had the wrong values.  It'll
-- be repopulated in code, in imap-db-database.vala.
--

UPDATE MessageTable SET internaldate_time_t = NULL;
