# CMake definitions to build sqlite3-unicodesn as a static library.  This file
# was added for Geary based on the project's Makefile.

# If you update this list, you should also double-check
# find_appropriate_search_stemmer() in src/engine/imap-db/imap-db-database.vala
set(STEMMERS
    danish dutch english finnish french german hungarian
    italian norwegian portuguese romanian russian spanish
    swedish turkish
)

set(SQLITE3_UNICODESN_SRC
    fts3_unicode2.c
    fts3_unicodesn.c
    static.c

    libstemmer_c/runtime/api_sq3.c
    libstemmer_c/runtime/utilities_sq3.c
)

add_definitions(
    -DSQLITE_ENABLE_FTS4
    -DSQLITE_ENABLE_FTS4_UNICODE61
)

include_directories(
    libstemmer_c/runtime
    libstemmer_c/src_c
)

foreach(stemmer ${STEMMERS})
    list(APPEND SQLITE3_UNICODESN_SRC libstemmer_c/src_c/stem_UTF_8_${stemmer}.c)
    add_definitions(-DWITH_STEMMER_${stemmer})
endforeach()

add_library(sqlite3-unicodesn STATIC ${SQLITE3_UNICODESN_SRC})
target_link_libraries(sqlite3-unicodesn sqlite3)
