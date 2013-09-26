--
-- Dummy database upgrade to fix the INTERNALDATE of messages that were accidentally stored in
-- localized format.  See src/engine/imap-db/imap-db-database.vala in post_upgrade() for the code
-- that runs the upgrade, and http://redmine.yorba.org/issues/7354 for more information.
--

