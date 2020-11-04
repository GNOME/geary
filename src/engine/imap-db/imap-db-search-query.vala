/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Internal implementation of {@link Geary.SearchQuery}.
 */
private class Geary.ImapDB.SearchQuery : Geary.SearchQuery {


    private const string EMAIL_TEXT_STEMMED_TERMS = "geary-stemmed-terms";


    internal bool has_stemmed_terms { get; private set; default = false; }

    private unowned SnowBall.Stemmer stemmer;


    public SearchQuery(Gee.List<Term> expression,
                       string raw,
                       SnowBall.Stemmer stemmer) {
        base(expression, raw);
        this.stemmer = stemmer;

        // Pre-stem search terms up front since the stemmed form is
        // needed in a few different places
        foreach (var term in this.expression) {
            // Use this brittle form of type checking for performance
            // (both here and further below in the class) - the Engine
            // controls the Term hierarchy the needed assumptions can
            // be made
            if (term.get_type() == typeof(EmailTextTerm)) {
                var text = (EmailTextTerm) term;
                if (text.matching_strategy.is_stemming_enabled()) {
                    stem_search_terms(text);
                }
            }
        }
    }

    internal Db.Statement get_search_query(
        Db.Connection cx,
        string? search_ids_sql,
        Gee.Collection<Geary.FolderPath>? folder_blacklist,
        int limit,
        int offset,
        GLib.Cancellable? cancellable
    ) throws GLib.Error {
        var sql = new GLib.StringBuilder();
        var conditions_added = false;

        sql.append("""
            SELECT mst.rowid
            FROM MessageSearchTable as mst
            INNER JOIN MessageTable AS mt ON mt.id = mst.rowid
            WHERE""");
        conditions_added = sql_add_term_conditions(sql, conditions_added);
        if (!String.is_empty(search_ids_sql)) {
            if (conditions_added) {
                sql.append(" AND");
            }
            sql.append(""" id IN (%s)""".printf(search_ids_sql));
        }
        sql.append("""
                ORDER BY mt.internaldate_time_t DESC""");
        if (limit > 0) {
            sql.append("""
                LIMIT ? OFFSET ?""");
        }

        Db.Statement stmt = cx.prepare(sql.str);
        int bind_index = sql_bind_term_conditions(stmt, false, 0);
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
        sql_bind_term_conditions(stmt, true, 0);
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
    private void stem_search_terms(EmailTextTerm text) {
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
            var is_first_match_term = true;
            sql.append(" MessageSearchTable MATCH '");
            foreach (var term in this.expression) {
                if (!is_first_match_term) {
                    sql.append(" AND");
                }

                if (term.is_negated) {
                    sql.append(" NOT");
                }

                if (term.get_type() == typeof(EmailTextTerm)) {
                    sql_add_email_text_term_conditions((EmailTextTerm) term, sql);
                } else if (term.get_type() == typeof(EmailFlagTerm)) {
                    sql.append(" ({flags} : \"' || ? || '\")");
                }

                is_first_match_term = false;
            }
            sql.append("'");
        }
        return have_added_sql_condition;
    }

    private void sql_add_email_text_term_conditions(EmailTextTerm text,
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

        var values = text.terms;
        var stemmed_values = text.get_data<Gee.List<string?>>(
            EMAIL_TEXT_STEMMED_TERMS
        );
        for (int i = 0; i < values.size; i++) {
            if (target != "") {
                sql.append_printf(" ({%s} :", target);
            }
            if (stemmed_values != null && stemmed_values[i] != null) {
                sql.append(" \"' || ? || '\"* OR \"' || ? || '\"*");
            } else {
                sql.append(" \"' || ? || '\"*");
            }
            if (target != "") {
                sql.append_c(')');
            }
        }
    }

    private int sql_bind_term_conditions(Db.Statement sql,
                                         bool text_only,
                                         int index)
        throws Geary.DatabaseError {
        int next_index = index;
        foreach (var term in this.expression) {
            var type = term.get_type();
            if (type == typeof(EmailTextTerm)) {
                var text = (EmailTextTerm) term;
                var stemmed_terms = text.get_data<Gee.List<string?>>(
                    EMAIL_TEXT_STEMMED_TERMS
                );
                for (int i = 0; i < text.terms.size; i++) {
                    sql.bind_string(next_index++, text.terms[i]);
                    if (stemmed_terms != null && stemmed_terms[i] != null) {
                        sql.bind_string(next_index++, stemmed_terms[i]);
                    }
                }
            } else if (type == typeof(EmailFlagTerm)) {
                var flag = (EmailFlagTerm) term;
                sql.bind_string(next_index++, flag.value.serialise());
            }
        }
        return next_index;
    }

}
