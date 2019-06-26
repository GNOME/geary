
--
-- Create ContactTable for autocompletion contacts.
--

CREATE TABLE ContactTable (
    id INTEGER PRIMARY KEY,
    normalized_email TEXT NOT NULL,
    real_name TEXT,
    email TEXT UNIQUE NOT NULL,
    highest_importance INTEGER NOT NULL
);

