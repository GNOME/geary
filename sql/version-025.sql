--
-- Index tables for fast lookup and association of conversations
--

CREATE TABLE ConversationTable (
    id INTEGER PRIMARY KEY,
    flags TEXT DEFAULT NULL
);

CREATE TABLE MessageConversationTable (
    id INTEGER PRIMARY KEY,
    conversation_id INTEGER REFERENCES ConversationTable DEFAULT NULL,
    message_id INTEGER REFERENCES MessageTable DEFAULT NULL,
    rfc822_message_id TEXT UNIQUE NOT NULL
);

CREATE INDEX MessageConversationTableConversationIDIndex ON MessageConversationTable(conversation_id);
CREATE INDEX MessageConversationTableMessageIDIndex ON MessageConversationTable(message_id);
CREATE INDEX MessageConversationTableRFC822MessageIDIndex ON MessageConversationTable(rfc822_message_id);

