--
-- Some queries that hit the MessageLocationTable, like those used by the email
-- prefetcher, were slow because we didn't have a covering index.  This makes
-- an index that *is* covering, for the cases in question anyway.  Since we
-- (should) never care about ordering without folder_id, and since folder_id
-- comes first here so this index effectively indexes queries on just that
-- field too, we can also drop the old, ineffective indices.
--

DROP INDEX MessageLocationTableFolderIdIndex;
DROP INDEX MessageLocationTableOrderingIndex;
CREATE INDEX MessageLocationTableFolderIDOrderingIndex
    ON MessageLocationTable(folder_id, ordering);
