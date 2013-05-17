
CC?=gcc
#CFLAGS=-W  -Wall -g -O0
CFLAGS?= -Os -DNDEBUG -s

DESTDIR?= /usr

STEMMERS?= danish dutch english finnish french german hungarian \
  italian norwegian porter portuguese romanian russian \
  spanish swedish

CFLAGS+= \
  -DSQLITE_ENABLE_FTS4 \
  -DSQLITE_ENABLE_FTS4_UNICODE61

SOURCES= \
  fts3_unicode2.c \
  fts3_unicodesn.c \
  extension.c

HEADERS=	fts3_tokenizer.h

INCLUDES= \
  -Ilibstemmer_c/runtime \
  -Ilibstemmer_c/src_c

LIBRARIES=	-lsqlite3

SNOWBALL_SOURCES= \
  libstemmer_c/runtime/api_sq3.c \
  libstemmer_c/runtime/utilities_sq3.c

SNOWBALL_HEADERS= \
  libstemmer_c/include/libstemmer.h \
  libstemmer_c/runtime/api.h \
  libstemmer_c/runtime/header.h

SNOWBALL_SOURCES+= $(foreach s, $(STEMMERS), libstemmer_c/src_c/stem_UTF_8_$(s).c)

SNOWBALL_HEADERS+= $(foreach s, $(STEMMERS), libstemmer_c/src_c/stem_UTF_8_$(s).h)

SNOWBALL_FLAGS+= $(foreach s, $(STEMMERS), -DWITH_STEMMER_$(s))

all: unicodesn.sqlext

unicodesn.sqlext: $(HEADERS) $(SOURCES) $(SNOWBALL_HEADERS) $(SNOWBALL_SOURCES)
	$(CC) $(CFLAGS) $(SNOWBALL_FLAGS) $(INCLUDES) -fPIC -shared -fvisibility=hidden -o $@ \
	   $(SOURCES) $(SNOWBALL_SOURCES) $(LIBRARIES)

clean:
	rm -f *.o unicodesn.sqlext

install: unicodesn.sqlext
	mkdir -p ${DESTDIR}/lib 2> /dev/null
	install -D -o root -g root -m 644 unicodesn.sqlext ${DESTDIR}/lib

.PHONY: clean install
