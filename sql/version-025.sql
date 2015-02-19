--
-- Index tables for fast lookup and association of conversations
--

CREATE TABLE ConversationTable (
    id INTEGER PRIMARY KEY,
    flags TEXT DEFAULT NULL
);

ALTER TABLE MessageTable ADD COLUMN conversation_id INTEGER REFERENCES ConversationTable DEFAULT NULL;

CREATE INDEX MessageTableConversationIDIndex ON MessageTable(conversation_id);

