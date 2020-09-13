--
-- Create MessageSearchTable
--

CREATE VIRTUAL TABLE MessageSearchTable USING fts4(
    body,
    attachment,
    subject,
    from_field,
    receivers,
    cc,
    bcc,

    tokenize=simple,
    prefix="2,4,6,8,10",
);
