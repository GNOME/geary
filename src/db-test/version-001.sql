
CREATE TABLE TestTable (
    id INTEGER PRIMARY KEY,
    str TEXT,
    num INTEGER
);

CREATE INDEX TestTableIntIndex ON TestTable(num);

