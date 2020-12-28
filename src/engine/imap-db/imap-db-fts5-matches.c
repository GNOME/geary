/*
 * Copyright (C) 2011 Nokia <ivan.frade@nokia.com>
 *
 * Author: Carlos Garnacho <carlos@lanedo.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301  USA
 */

/*
 * Borrowed from the Tracker project (see: tracker-fts-tokenizer.c)
 * and adapted for Geary by Michael Gratton <mike@vee.net>.
 */

#include <sqlite3.h>
#include <glib.h>

#define unused __attribute__((unused))


typedef struct {
    int start;
    int end;
} Offset;

static int
offsets_tokenizer_func (void       *data,
                        unused int  flags,
                        unused const char *token,
                        unused int  n_token,
                        int         start,
                        int         end)
{
    GArray *offsets = data;
    Offset offset = { 0 };
    offset.start = start;
    offset.end = end;
    g_array_append_val(offsets, offset);
    return SQLITE_OK;
}

static void
geary_matches (const Fts5ExtensionApi  *api,
               Fts5Context             *fts_ctx,
               sqlite3_context         *ctx,
               int                      n_args,
               unused sqlite3_value   **args)
{
    GString *str;
    int rc, n_hits, i;
    GArray *offsets = NULL;
    gint cur_col = -1;
    gboolean first = TRUE;

    if (n_args > 0) {
        sqlite3_result_error(ctx, "Invalid argument count", -1);
        return;
    }

    rc = api->xInstCount(fts_ctx, &n_hits);
    if (rc != SQLITE_OK) {
        sqlite3_result_null(ctx);
        return;
    }

    str = g_string_new(NULL);

    for (i = 0; i < n_hits; i++) {
        int phrase, col, n_token;
        const char *text;
        int length;
        Offset offset;

        rc = api->xInst(fts_ctx, i, &phrase, &col, &n_token);
        if (rc != SQLITE_OK)
            break;

        if (first || cur_col != col) {
            if (offsets) {
                g_array_free(offsets, TRUE);
            }

            rc = api->xColumnText(fts_ctx, col, &text, &length);
            if (rc != SQLITE_OK)
                break;

            offsets = g_array_new(FALSE, FALSE, sizeof(Offset));
            rc = api->xTokenize(fts_ctx,
                                text,
                                length,
                                offsets,
                                &offsets_tokenizer_func);
            if (rc != SQLITE_OK) {
                break;
            }

            cur_col = col;
        }

        first = FALSE;

        if (str->len != 0) {
            g_string_append_c(str, ',');
        }

        offset = g_array_index(offsets, Offset, n_token);
        g_string_append_len(str, text + offset.start, offset.end - offset.start);
    }

    if (offsets) {
        g_array_free (offsets, TRUE);
    }

    if (rc == SQLITE_OK) {
        sqlite3_result_text (ctx, str->str, str->len, g_free);
        g_string_free (str, FALSE);
    } else {
        sqlite3_result_error_code (ctx, rc);
        g_string_free (str, TRUE);
    }
}

static fts5_api *get_fts5_api (sqlite3 *db) {
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

gboolean sqlite3_register_fts5_matches(sqlite3 *db) {
    fts5_api *api;
    int rc = SQLITE_OK;

    api = get_fts5_api(db);
    if (!api) {
        return FALSE;
    }

    rc = api->xCreateFunction(api,
                              "geary_matches",
                              NULL,
                              &geary_matches,
                              NULL);

    return (rc == SQLITE_OK) ? TRUE : FALSE;
}
