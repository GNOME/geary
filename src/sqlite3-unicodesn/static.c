/*
** 2013 May 16
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
******************************************************************************
**
** This file was added for Geary to allow use as a static library.
**
*/
#include <sqlite3.h>
#include "fts3_unicodesn.h"

/*
** Register a tokenizer implementation with FTS3 or FTS4.
*/
static int registerTokenizer(
  sqlite3 *db,
  char *zName,
  const sqlite3_tokenizer_module *p
){
  int rc;
  sqlite3_stmt *pStmt;
  const char *zSql = "SELECT fts3_tokenizer(?, ?)";

  rc = sqlite3_prepare_v2(db, zSql, -1, &pStmt, 0);
  if( rc!=SQLITE_OK ){
    return rc;
  }

  sqlite3_bind_text(pStmt, 1, zName, -1, SQLITE_STATIC);
  sqlite3_bind_blob(pStmt, 2, &p, sizeof(p), SQLITE_STATIC);
  sqlite3_step(pStmt);

  return sqlite3_finalize(pStmt);
}

int sqlite3_unicodesn_register_tokenizer(sqlite3 *db)
{
    static const sqlite3_tokenizer_module *tokenizer = 0;
    if (!tokenizer)
        sqlite3Fts3UnicodeSnTokenizer(&tokenizer);
    return registerTokenizer(db, TOKENIZER_NAME, tokenizer);
}
