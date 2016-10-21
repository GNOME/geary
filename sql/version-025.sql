--
-- Rebuild corrupted MessageSearchTable indexes. Bug 772522.
--

-- According to the FTS3 docs <https://www.sqlite.org/fts3.html>, this
-- needs to be done "whenever the implementation of a custom tokeniser
-- changes", but Geary is also seeing the indexes being corrupted when
-- doing UPDATEs on MessageSearchTable. Bug 772522 has replaced use of
-- that with a SELECT/DELETE/INSERT which does not result in a
-- corrupted index, so do a rebuild here to ensure everyone's is not
-- back in order.
INSERT INTO MessageSearchTable(MessageSearchTable) VALUES('rebuild');

-- While we're here, optimise it as well.
INSERT INTO MessageSearchTable(MessageSearchTable) VALUES('optimize');
