/*
 * Parts of the code below have been taken from
 * `ext/fts3/fts3_tokenizer.h` SQLite source code repository with the
 * following copyright notice:
 *
 * "The author disclaims copyright to this source code."
 *
 * Parts of this code have been taken from
 * <https://www.sqlite.org/fts3.html>, which carries the following
 * copyright notice:
 *
 * All of the code and documentation in SQLite has been dedicated to
 * the public domain by the authors. All code authors, and
 * representatives of the companies they work for, have signed
 * affidavits dedicating their contributions to the public domain and
 * originals of those signed affidavits are stored in a firesafe at
 * the main offices of Hwaci. Anyone is free to copy, modify, publish,
 * use, compile, sell, or distribute the original SQLite code, either
 * in source code form or as a compiled binary, for any purpose,
 * commercial or non-commercial, and by any means.
 *
 *                  --- <https://www.sqlite.org/copyright.html>
 */

/*
 * Defines SQLite FTS3/4 tokeniser with the same name as the one used
 * in Geary prior to version 3.40, so that database upgrades that
 * still reference this tokeniser can complete successfully.
 */

#define TOKENIZER_NAME "unicodesn"

#include <sqlite3.h>
#include <string.h>

#ifndef _FTS3_TOKENIZER_H_
#define _FTS3_TOKENIZER_H_

typedef struct sqlite3_tokenizer_module sqlite3_tokenizer_module;
typedef struct sqlite3_tokenizer sqlite3_tokenizer;
typedef struct sqlite3_tokenizer_cursor sqlite3_tokenizer_cursor;

struct sqlite3_tokenizer_module {
  int iVersion;
  int (*xCreate)(
    int argc,                           /* Size of argv array */
    const char *const*argv,             /* Tokenizer argument strings */
    sqlite3_tokenizer **ppTokenizer     /* OUT: Created tokenizer */
  );
  int (*xDestroy)(sqlite3_tokenizer *pTokenizer);
  int (*xOpen)(
    sqlite3_tokenizer *pTokenizer,       /* Tokenizer object */
    const char *pInput, int nBytes,      /* Input buffer */
    sqlite3_tokenizer_cursor **ppCursor  /* OUT: Created tokenizer cursor */
  );
  int (*xClose)(sqlite3_tokenizer_cursor *pCursor);
  int (*xNext)(
    sqlite3_tokenizer_cursor *pCursor,   /* Tokenizer cursor */
    const char **ppToken, int *pnBytes,  /* OUT: Normalized text for token */
    int *piStartOffset,  /* OUT: Byte offset of token in input buffer */
    int *piEndOffset,    /* OUT: Byte offset of end of token in input buffer */
    int *piPosition      /* OUT: Number of tokens returned before this one */
  );
  int (*xLanguageid)(sqlite3_tokenizer_cursor *pCsr, int iLangid);
};

struct sqlite3_tokenizer {
  const sqlite3_tokenizer_module *pModule;  /* The module for this tokenizer */
  /* Tokenizer implementations will typically add additional fields */
};

struct sqlite3_tokenizer_cursor {
  sqlite3_tokenizer *pTokenizer;       /* Tokenizer for this cursor. */
  /* Tokenizer implementations will typically add additional fields */
};

int fts3_global_term_cnt(int iTerm, int iCol);
int fts3_term_cnt(int iTerm, int iCol);


#endif /* _FTS3_TOKENIZER_H_ */

static int registerTokenizer(
  sqlite3 *db,
  char *zName,
  const sqlite3_tokenizer_module *p
){
  int rc;
  sqlite3_stmt *pStmt;
  const char *zSql = "SELECT fts3_tokenizer(?, ?)";

  /* Enable the 2-argument form of fts3_tokenizer in SQLite >= 3.12 */
  rc = sqlite3_db_config(db,SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER,1,0);
  if( rc!=SQLITE_OK ){
    return rc;
  }

  rc = sqlite3_prepare_v2(db, zSql, -1, &pStmt, 0);
  if( rc!=SQLITE_OK ){
    return rc;
  }

  sqlite3_bind_text(pStmt, 1, zName, -1, SQLITE_STATIC);
  sqlite3_bind_blob(pStmt, 2, &p, sizeof(p), SQLITE_STATIC);
  sqlite3_step(pStmt);

  return sqlite3_finalize(pStmt);
}

int queryTokenizer(
  sqlite3 *db,
  char *zName,
  const sqlite3_tokenizer_module **pp
){
  int rc;
  sqlite3_stmt *pStmt;
  const char *zSql = "SELECT fts3_tokenizer(?)";

  *pp = 0;
  rc = sqlite3_prepare_v2(db, zSql, -1, &pStmt, 0);
  if( rc!=SQLITE_OK ){
    return rc;
  }

  sqlite3_bind_text(pStmt, 1, zName, -1, SQLITE_STATIC);
  if( SQLITE_ROW==sqlite3_step(pStmt) ){
    if( sqlite3_column_type(pStmt, 0)==SQLITE_BLOB ){
      memcpy(pp, sqlite3_column_blob(pStmt, 0), sizeof(*pp));
    }
  }

  return sqlite3_finalize(pStmt);
}

#include <stdio.h>

int sqlite3_register_legacy_tokenizer(sqlite3 *db) {
    static const sqlite3_tokenizer_module *tokenizer = 0;
    if (!tokenizer) {
        queryTokenizer(db, "simple", &tokenizer);
    }
    return registerTokenizer(db, TOKENIZER_NAME, tokenizer);
}
