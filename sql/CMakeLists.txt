set(SQL_DEST share/geary/sql)

install(FILES Create.sql DESTINATION ${SQL_DEST})
install(FILES Version-002.sql DESTINATION ${SQL_DEST})
install(FILES Version-003.sql DESTINATION ${SQL_DEST})

