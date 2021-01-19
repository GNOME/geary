/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A search query implementation that provides full-text search.
 */
internal class Geary.FtsSearchQuery : Geary.SearchQuery {


    private const string EMAIL_TEXT_STEMMED_TERMS = "geary-stemmed-terms";


    internal bool has_stemmed_terms { get; private set; default = false; }

    private bool is_all_negated = true;

    private unowned SnowBall.Stemmer stemmer;


    public FtsSearchQuery(Gee.List<SearchQuery.Term> expression,
                          string raw,
                          SnowBall.Stemmer stemmer) {
        base(expression, raw);
        this.stemmer = stemmer;

        foreach (var term in this.expression) {
            // Use this brittle form of type checking for performance
            // (both here and further below in the class) - the Engine
            // controls the Term hierarchy the needed assumptions can
            // be made
            if (term.get_type() == typeof(SearchQuery.EmailTextTerm)) {
                // Pre-stem search terms up front since the stemmed
                // form is needed in a few different places
                var text = (SearchQuery.EmailTextTerm) term;
                if (text.matching_strategy.is_stemming_enabled()) {
                    stem_search_terms(text);
                }
            }
            if (!term.is_negated) {
                this.is_all_negated = false;
            }
        }
    }

    internal Db.Statement get_search_query(
        Db.Connection cx,
        string? search_ids_sql,
        string? excluded_folder_ids_sql,
        bool exclude_folderless,
        int limit,
        int offset
    ) throws GLib.Error {
        var sql = new GLib.StringBuilder();

        // Select distinct since messages may exist in more than one
        // folder.
        sql.append("""
                SELECT DISTINCT mt.id
                FROM MessageTable AS mt
                INDEXED BY MessageTableInternalDateTimeTIndex""");

        // If excluding folderless messages, an inner join on
        // MessageLocationTable will cause them to be excluded
        // automatically. Otherwise a left join always required to
        // exclude messages marked for deletion, even if there are no
        // folder exclusions.
        if (exclude_folderless) {
            sql.append("""
                INNER JOIN MessageLocationTable AS mlt ON mt.id = mlt.message_id""");
        } else {
            sql.append("""
                LEFT JOIN MessageLocationTable AS mlt ON mt.id = mlt.message_id""");
        }

        var conditions_added = false;
        sql.append("""
                WHERE""");

        // Folder exclusions
        if (excluded_folder_ids_sql != null) {
            sql.append_printf(
                " mlt.folder_id NOT IN (%s)",
                excluded_folder_ids_sql
            );
            conditions_added = true;
        }

        // FTS match exclusions
        if (!this.expression.is_empty) {
            if (conditions_added) {
                sql.append(" AND");
            }
            sql.append(
                this.is_all_negated
                ? " mt.id NOT IN"
                : " mt.id IN"
            );
            sql.append(
                " (SELECT mst.rowid FROM MessageSearchTable as mst WHERE "
            );
            sql_add_term_conditions(sql, false);
            sql.append_c(')');
            conditions_added = true;
        }

        // Email id exclusions
        if (!String.is_empty(search_ids_sql)) {
            if (conditions_added) {
                sql.append(" AND");
            }
            sql.append(""" mt.id IN (%s)""".printf(search_ids_sql));
        }

        // Marked as deleted (but not folderless) exclusions
        if (conditions_added) {
            sql.append(" AND");
        }
        sql.append(" mlt.remove_marker IN (0, null)");

        // Ordering
        sql.append("""
                ORDER BY mt.internaldate_time_t DESC""");

        // Limit exclusions
        if (limit > 0) {
            sql.append("""
                LIMIT ? OFFSET ?""");
        }

        Db.Statement stmt = cx.prepare(sql.str);
        int bind_index = sql_bind_term_conditions(stmt, 0);
        if (limit > 0) {
            stmt.bind_int(bind_index++, limit);
            stmt.bind_int(bind_index++, offset);
        }

        return stmt;
    }

    internal Db.Statement get_match_query(
        Db.Connection cx,
        string? search_ids_sql
    ) throws GLib.Error {
        var sql = new GLib.StringBuilder();
        sql.append("""
            SELECT mst.rowid, geary_matches(MessageSearchTable)
            FROM MessageSearchTable as mst
            WHERE rowid IN (
        """);
        sql.append(search_ids_sql);
        sql.append(") AND ");
        sql_add_term_conditions(sql, false);

        Db.Statement stmt = cx.prepare(sql.str);
        sql_bind_term_conditions(stmt, 0);
        return stmt;
    }

    /**
     * Applies stemming for the given term to a specific term value.
     *
     * Prior experience with the Snowball stemmer indicates it is too
     * aggressive for our tastes when coupled with prefix-matching of
     * all unquoted terms. See
     * https://bugzilla.gnome.org/show_bug.cgi?id=713179 and
     * https://bugzilla.gnome.org/show_bug.cgi?id=720361
     *
     * This method is part of a larger strategy designed to dampen
     * that aggressiveness without losing the benefits of stemming
     * entirely: The database's FTS table uses no stemming, but
     * libstemmer is used to generate stemmed search terms.
     * Post-search processing is then to strip results which are too
     * "greedy" due to prefix-matching the stemmed variant.
     *
     * Some heuristics are in place simply to determine if stemming
     * should occur:
     *
     * # If stemming is unallowed, no stemming occurs.
     * # If the term is < min. term length for stemming, no stemming
     *   occurs.
     * # If the stemmer returns a stem that is the same as the
     *   original term, no stemming occurs.
     * # If the difference between the stemmed word and the original
     *   term is more than maximum allowed, no stemming occurs.  This
     *   works under the assumption that if the user has typed a long
     *   word, they do not want to "go back" to searching for a much
     *   shorter version of it.  (For example, "accountancies" stems
     *   to "account").
     *
     * Otherwise, the stem for the term is returned.
     */
    private void stem_search_terms(SearchQuery.EmailTextTerm text) {
        var stemmed_terms = new Gee.ArrayList<string?>();
        foreach (var term in text.terms) {
            int term_length = term.length;
            string? stemmed = null;
            if (term_length > text.matching_strategy.get_min_term_length_for_stemming()) {
                stemmed = this.stemmer.stem(term, term_length);
                if (String.is_empty(stemmed) ||
                    term == stemmed ||
                    term_length - stemmed.length >
                    text.matching_strategy.get_max_difference_term_stem_lengths()) {
                    stemmed = null;
                }
            }
            if (stemmed != null) {
                this.has_stemmed_terms = true;
                debug(@"Search term \"$term\" stemmed to \"$stemmed\"");
            } else {
                debug(@"Search term \"$term\" not stemmed");
            }
            stemmed_terms.add(stemmed);
        }
        text.set_data(EMAIL_TEXT_STEMMED_TERMS, stemmed_terms);
    }

    private bool sql_add_term_conditions(GLib.StringBuilder sql,
                                         bool have_added_sql_condition) {
        if (!this.expression.is_empty) {
            if (have_added_sql_condition) {
                sql.append(" AND");
            }
            have_added_sql_condition = true;
            sql.append(" MessageSearchTable MATCH '");

            // Add all non-negated terms first, since NOT in FTS5 is a
            // binary operator (not unary, FFS), and hence all negated
            // clauses must follow a positive operator and a single
            // NOT clause. For example, for positive terms a,c and
            // negated terms b,d, the match value must be structured
            // as: (a AND c) NOT (b AND d)

            var is_first_positive_term = true;
            foreach (var term in this.expression) {
                if (!term.is_negated) {
                    if (is_first_positive_term) {
                        sql.append(" (");
                    } else {
                        sql.append(" AND");
                    }
                    sql_add_term_condition(sql, term);
                    is_first_positive_term = false;
                }
            }
            if (!is_first_positive_term) {
                sql.append_c(')');
            }

            var is_first_negated_term = true;
            foreach (var term in this.expression) {
                if (term.is_negated) {
                    if (is_first_negated_term) {
                        // If all negated, there won't be any positive
                        // terms above, and the MATCH will be used as
                        // an exclusion instead, so the NOT operator
                        // is not required.
                        if (!this.is_all_negated) {
                            sql.append(" NOT (");
                        } else {
                            sql.append(" (");
                        }
                    } else {
                        sql.append(" AND");
                    }
                    sql_add_term_condition(sql, term);
                    is_first_negated_term = false;
                }
            }
            if (!is_first_negated_term) {
                sql.append_c(')');
            }

            sql.append("'");
        }
        return have_added_sql_condition;
    }

    private inline void sql_add_term_condition(GLib.StringBuilder sql,
                                               SearchQuery.Term term) {
        if (term.get_type() == typeof(SearchQuery.EmailTextTerm)) {
            sql_add_email_text_term_conditions((SearchQuery.EmailTextTerm) term, sql);
        } else if (term.get_type() == typeof(SearchQuery.EmailFlagTerm)) {
            sql.append(" ({flags} : \"' || ? || '\")");
        }
    }

    private inline void sql_add_email_text_term_conditions(SearchQuery.EmailTextTerm text,
                                                           GLib.StringBuilder sql) {
        var target = "";
        switch (text.target) {
        case ALL:
            target = "";
            break;
        case TO:
            target = "receivers";
            break;
        case CC:
            target = "cc";
            break;
        case BCC:
            target = "bcc";
            break;
        case FROM:
            target = "from";
            break;
        case SUBJECT:
            target = "subject";
            break;
        case BODY:
            target = "body";
            break;
        case ATTACHMENT_NAME:
            target = "attachments";
            break;
        }

        sql.append(" (");

        var values = text.terms;
        var stemmed_values = text.get_data<Gee.List<string?>>(
            EMAIL_TEXT_STEMMED_TERMS
        );
        var is_first_disjunct = true;
        for (int i = 0; i < values.size; i++) {
            if (!is_first_disjunct) {
                sql.append(" OR");
            }
            if (target != "") {
                sql.append_printf("{%s} :", target);
            }
            if (stemmed_values != null && stemmed_values[i] != null) {
                // Original is not a prefix match, stemmed is
                sql.append(" \"' || ? || '\" OR \"' || ? || '\"*");
            } else if (text.matching_strategy != EXACT) {
                // A regular match, do a suffix match
                sql.append(" \"' || ? || '\"*");
            } else {
                // EXACT is not a prefix match
                sql.append(" \"' || ? || '\"");
            }
            is_first_disjunct = false;
        }
        sql.append_c(')');
    }

    private int sql_bind_term_conditions(Db.Statement sql,
                                         int index)
        throws Geary.DatabaseError {
        int next_index = index;
        // Per sql_add_term_conditions, add all non-negated terms
        // first before adding any negated terms.
        foreach (var term in this.expression) {
            if (!term.is_negated) {
                next_index = sql_bind_term_condition(sql, term, next_index);
            }
        }
        foreach (var term in this.expression) {
            if (term.is_negated) {
                next_index = sql_bind_term_condition(sql, term, next_index);
            }
        }
        return next_index;
    }

    private inline int sql_bind_term_condition(Db.Statement sql,
                                               SearchQuery.Term term,
                                               int index)
        throws Geary.DatabaseError {
        int next_index = index;
        var type = term.get_type();
        if (type == typeof(SearchQuery.EmailTextTerm)) {
            var text = (SearchQuery.EmailTextTerm) term;
            var stemmed_terms = text.get_data<Gee.List<string?>>(
                EMAIL_TEXT_STEMMED_TERMS
            );
            for (int i = 0; i < text.terms.size; i++) {
                sql.bind_string(next_index++, text.terms[i]);
                if (stemmed_terms != null && stemmed_terms[i] != null) {
                    sql.bind_string(next_index++, stemmed_terms[i]);
                }
            }
        } else if (type == typeof(SearchQuery.EmailFlagTerm)) {
            var flag = (SearchQuery.EmailFlagTerm) term;
            sql.bind_string(next_index++, flag.value.serialise());
        }
        return next_index;
    }

}
