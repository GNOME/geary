--
-- For a while there, we weren't properly indexing attachment filenames in the
-- search table.  To be proper (and since this is right before a major release)
-- we want to make sure anyone who's been running the dailies has a good
-- database, which unfortunately means ditching the search table and letting
-- Geary recreate it properly.
--

DELETE FROM MessageSearchTable
