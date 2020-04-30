sqlite3_unicodesn_sources = [
 'fts3_unicode2.c',
 'fts3_unicodesn.c',
 'static.c',

 'libstemmer_c' / 'runtime' / 'api_sq3.c',
 'libstemmer_c' / 'runtime' / 'utilities_sq3.c',
]

sqlite3_unicodesn_c_flags = [
  '-DSQLITE_ENABLE_FTS4',
  '-DSQLITE_ENABLE_FTS4_UNICODE61',
]

sqlite3_unicodesn_stemmers = [
  'danish',
  'dutch',
  'english',
  'finnish',
  'french',
  'german',
  'hungarian',
  'italian',
  'norwegian',
  'portuguese',
  'romanian',
  'russian',
  'spanish',
  'swedish',
  'turkish',
]

foreach stemmer: sqlite3_unicodesn_stemmers
  sqlite3_unicodesn_sources += 'libstemmer_c/src_c/stem_UTF_8_@0@.c'.format(stemmer)
  sqlite3_unicodesn_c_flags += '-DWITH_STEMMER_@0@'.format(stemmer)
endforeach

sqlite3_unicodesn_includes = [
  include_directories('libstemmer_c/runtime'),
  include_directories('libstemmer_c/src_c'),
]

sqlite3_unicodesn_lib = static_library('sqlite3-unicodesn',
  sqlite3_unicodesn_sources,
  dependencies: sqlite,
  c_args: sqlite3_unicodesn_c_flags,
  include_directories: sqlite3_unicodesn_includes,
)
