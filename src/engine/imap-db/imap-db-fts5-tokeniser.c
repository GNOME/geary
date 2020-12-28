/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1

#include <glib.h>
#include <gmodule.h>
#include <unicode/ubrk.h>
#include <unicode/unorm2.h>
#include <unicode/ustring.h>
#include "unicode/utf.h"
#include "unicode/utypes.h"

#define unused __attribute__((unused))

// Full text search tokeniser for SQLite. This exists since SQLite's
// existing Unicode tokeniser doesn't work with languages that don't
// use spaces as word boundaries.
//
// When generating tokens, the follow process is applied to text using
// the ICU library:
//
// 1. ICU NFKC_Casefold normalisation, handles normalisation, case
//    folding and removal of ignorable characters such as accents.
//
// 2. ICU word-boundary tokenisation, splits both on words at spaces
//    and other punctuation, and also using a dictionary lookup for
//    languages that do not use spaces (CJK, Thai, etc)
//
// Note: Since SQLite is single-threaded, it's safe to use single
// instances of ICU services for all calls for a single tokeniser.

#define NORM_BUF_LEN 8
#define TOKEN_BUF_LEN 8

typedef struct {
    // Singleton object, threadsafe, does not need to be deleted.
    const UNormalizer2 * norm;

    // Stateful object, not threadsafe, must be deleted.
    UBreakIterator *iter;
} IcuTokeniser;


static int icu_create(unused void *context,
                      unused const char **args,
                      unused int n_args,
                      Fts5Tokenizer **ret) {
    const UNormalizer2 *norm;
    UBreakIterator *iter;
    IcuTokeniser *tokeniser;
    UErrorCode err = U_ZERO_ERROR;

    norm = unorm2_getNFKCCasefoldInstance(&err);
    if (U_FAILURE(err)) {
        g_warning("Error constructing ICU normaliser: %s", u_errorName(err));
        return SQLITE_ABORT;
    }

    // The given locale doesn't matter here since it ICU doesn't
    // (currently) use different rules for different word breaking
    // languages that uses spaces as word boundaries, and uses
    // dictionary look-ups for CJK and other scripts that don't.
    iter = ubrk_open(UBRK_WORD, "en", NULL, 0, &err);
    if (U_FAILURE(err)) {
        g_warning("Error constructing ICU word-breaker: %s", u_errorName(err));
        ubrk_close(tokeniser->iter);
        return SQLITE_ABORT;
    }

    tokeniser = g_new0(IcuTokeniser, 1);
    tokeniser->norm = norm;
    tokeniser->iter = iter;
    *ret = (Fts5Tokenizer *) tokeniser;

    return SQLITE_OK;
}

static void icu_delete(Fts5Tokenizer *fts5_tokeniser) {
    IcuTokeniser *tokeniser = (IcuTokeniser *) fts5_tokeniser;

    ubrk_close(tokeniser->iter);
    g_free(tokeniser);
}

static int icu_tokenise(Fts5Tokenizer *fts5_tokeniser,
                        void *context,
                        unused int flags,
                        const char *chars,
                        int32_t chars_len,
                        int (*token_callback)(void*, int, const char*, int, int, int)) {
    int ret = SQLITE_OK;
    IcuTokeniser *tokeniser = (IcuTokeniser *) fts5_tokeniser;
    UErrorCode err = U_ZERO_ERROR;

    const UNormalizer2 *norm = tokeniser->norm;
    GArray *wide_chars = NULL;
    GArray *wide_offsets = NULL;
    UChar *wide_data = NULL;
    gsize wide_data_len_long = 0;
    int32_t wide_data_len = 0;

    UChar norm_buf[NORM_BUF_LEN] = {0};

    UBreakIterator *iter = tokeniser->iter;
    int32_t start_index, current_index = 0;
    char *token_buf = NULL;
    int32_t token_buf_len = NORM_BUF_LEN;

    // Normalisation.
    //
    // SQLite needs the byte-index of tokens found in the chars, but
    // ICU doesn't support UTF-8-based normalisation. So convert UTF-8
    // input to UTF-16 char-by-char and record the byte offsets for
    // each, so that when converting back to UTF-8 the byte offsets
    // can be determined.

    wide_chars = g_array_sized_new(FALSE, FALSE, sizeof(UChar), chars_len);
    wide_offsets = g_array_sized_new(FALSE, FALSE, sizeof(int32_t), chars_len);

    for (int32_t byte_offset = 0; byte_offset < chars_len;) {
        UChar wide_char;
        int32_t norm_len;
        int32_t start_byte_offset = byte_offset;

        U8_NEXT_OR_FFFD(chars, byte_offset, chars_len, wide_char);
        norm_len = unorm2_normalize(norm,
                                    &wide_char, 1,
                                    norm_buf, NORM_BUF_LEN,
                                    &err);
        if (U_FAILURE(err)) {
            g_warning("Token text normalisation failed");
            err = SQLITE_ABORT;
            goto cleanup;
        }

        // NFKC may decompose a single character into multiple
        // characters, e.g. 'ﬁ' into "fi", '…' into "...".
        for (int i = 0; i < norm_len; i++) {
            g_array_append_val(wide_chars, norm_buf[i]);
            g_array_append_val(wide_offsets, start_byte_offset);
        }
    }

    // Word breaking.
    //
    // UTF-16 is passed to the tokeniser, hence its indexes are
    // character-based. Use the offset array to convert those back to
    // byte indexes for individual tokens.

    wide_data = (UChar *) g_array_steal(wide_chars, &wide_data_len_long);
    wide_data_len = (int32_t) wide_data_len_long;

    ubrk_setText(iter, wide_data, wide_data_len, &err);
    if (U_FAILURE(err)) {
        err = SQLITE_ABORT;
        g_warning("Setting word break iterator text failed");
        goto cleanup;
    }
    start_index = 0;
    current_index = ubrk_first(iter);
    token_buf = g_malloc0(sizeof(char) * token_buf_len);
    while (current_index != UBRK_DONE && ret == SQLITE_OK) {
        int32_t status = ubrk_getRuleStatus(iter);
        int32_t token_char_len = current_index - start_index;
        if (token_char_len > 0 &&
            !(status >= UBRK_WORD_NONE && status < UBRK_WORD_NONE_LIMIT) &&
            !(status >= UBRK_WORD_NUMBER && status < UBRK_WORD_NUMBER_LIMIT)) {
            int32_t token_byte_len = 0;
            int32_t token_byte_start = 0;
            int32_t token_byte_end = 0;

            for (;;) {
                u_strToUTF8WithSub(token_buf, token_buf_len, &token_byte_len,
                                   wide_data + start_index, token_char_len,
                                   0xFFFD, NULL,
                                   &err);

                if (U_SUCCESS(err)) {
                    break;
                } else if (err == U_BUFFER_OVERFLOW_ERROR) {
                    token_buf_len *= 2;
                    token_buf = g_realloc(token_buf, sizeof(char) * token_buf_len);
                    err = U_ZERO_ERROR;
                } else {
                    err = SQLITE_ABORT;
                    g_warning("Conversion to UTF-8 failed");
                    goto cleanup;
                }
            }

            token_byte_start = g_array_index(wide_offsets, int32_t, start_index);
            if (current_index < wide_data_len) {
                token_byte_end = g_array_index(wide_offsets, int32_t, current_index);
            } else {
                token_byte_end = chars_len;
            }

            ret = token_callback(context,
                                 0,
                                 token_buf,
                                 token_byte_len,
                                 token_byte_start,
                                 token_byte_end);
        }

        start_index = current_index;
        current_index = ubrk_next(iter);
    }

 cleanup:
    g_free(wide_data);
    g_array_unref(wide_chars);
    g_array_unref(wide_offsets);
    g_free(token_buf);

    return ret;
}

static fts5_api *get_fts5_api(sqlite3 *db) {
    int rc = SQLITE_OK;
    sqlite3_stmt *stmt;
    fts5_api *api = NULL;

    rc = sqlite3_prepare_v2(db, "SELECT fts5(?1)",
                                -1, &stmt, 0);
    if (rc != SQLITE_OK) {
        return NULL;
    }

    sqlite3_bind_pointer(stmt, 1, (void*) &api, "fts5_api_ptr", NULL);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    return api;
}

static const fts5_tokenizer icu_tokeniser = {
    icu_create,
    icu_delete,
    icu_tokenise
};

gboolean sqlite3_register_fts5_tokeniser(sqlite3 *db) {
    fts5_api *api;
    fts5_tokenizer *tokeniser = (fts5_tokenizer *) &icu_tokeniser;
    int rc = SQLITE_OK;

    api = get_fts5_api(db);
    if (!api) {
        return FALSE;
    }

    rc = api->xCreateTokenizer(api,
                               "geary_tokeniser",
                               NULL,
                               tokeniser,
                               NULL);

    return (rc == SQLITE_OK) ? TRUE : FALSE;
}

// Entry point for external loadable library, required when using
// command line SQLite tool. The name of this function must match the
// name of the shared module.
int sqlite3_gearytokeniser_init(sqlite3 *db,
                                unused char **error_message,
                                const sqlite3_api_routines *api) {
    g_info("Loading geary_tokeniser\n");
    SQLITE_EXTENSION_INIT2(api);
    return sqlite3_register_fts5_tokeniser(db) ? SQLITE_OK : SQLITE_ABORT;
}
