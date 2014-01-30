--
-- We're now keeping sent mail around after sending, so we can also push it up
-- to the Sent Mail folder.  This column lets us keep track of the state of
-- messages in the outbox.
--

ALTER TABLE SmtpOutboxTable ADD COLUMN sent INTEGER DEFAULT 0;
