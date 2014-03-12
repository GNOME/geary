--
-- We had previously incorrectly included an id column in the search table.
-- The code is fixed to use docid instead, so we just empty the table and let
-- the natural search table population process make things right.
--

DELETE FROM MessageSearchTable
