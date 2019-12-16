/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Internal implementation of {@link Geary.SearchQuery}.
 */
private class Geary.ImapDB.SearchQuery : Geary.SearchQuery {

    // These characters are chosen for being commonly used to continue a single word (such as
    // extended last names, i.e. "Lars-Eric") or in terms commonly searched for in an email client,
    // i.e. unadorned mailbox addresses.  Note that characters commonly used for wildcards or that
    // would be interpreted as wildcards by SQLite are not included here.
    private const unichar[] SEARCH_TERM_CONTINUATION_CHARS = { '-', '_', '.', '@' };

    // Search operator field names, eg: "to:foo@example.com" or "is:unread"
    private const string SEARCH_OP_ATTACHMENT = "attachments";
    private const string SEARCH_OP_BCC = "bcc";
    private const string SEARCH_OP_BODY = "body";
    private const string SEARCH_OP_CC = "cc";
    private const string SEARCH_OP_FROM = "\"from\"";
    private const string SEARCH_OP_IS = "is";
    private const string SEARCH_OP_SUBJECT = "subject";
    private const string SEARCH_OP_TO = "receivers";

    // Operators allowing finding mail addressed to "me"
    private const string[] SEARCH_OP_TO_ME_FIELDS = {
        SEARCH_OP_BCC,
        SEARCH_OP_CC,
        SEARCH_OP_TO,
    };

    // The addressable op value for "me"
    private const string SEARCH_OP_ADDRESSABLE_VALUE_ME = "me";

    // Search operator field values
    private const string SEARCH_OP_VALUE_READ = "read";
    private const string SEARCH_OP_VALUE_STARRED = "starred";
    private const string SEARCH_OP_VALUE_UNREAD = "unread";


    /**
     * Various associated state with a single term in a search query.
     */
    internal class Term : GLib.Object {

        /**
         * The original tokenized search term with minimal other processing performed.
         *
         * For example, punctuation might be removed, but no casefolding has occurred.
         */
        public string original { get; private set; }

        /**
         * The parsed tokenized search term.
         *
         * Casefolding and other normalizing text operations have been performed.
         */
        public string parsed { get; private set; }

        /**
         * The stemmed search term.
         *
         * Only used if stemming is being done ''and'' the stem is different than the {@link parsed}
         * term.
         */
        public string? stemmed { get; private set; }

        /**
         * A list of terms ready for binding to an SQLite statement.
         *
         * This should include prefix operators and quotes (i.e. ["party"] or [party*]).  These texts
         * are guaranteed not to be null or empty strings.
         */
        public Gee.List<string> sql { get; private set; default = new Gee.ArrayList<string>(); }

        /**
         * Returns true if the {@link parsed} term is exact-match only (i.e. starts with quotes) and
         * there is no {@link stemmed} variant.
         */
        public bool is_exact { get { return parsed.has_prefix("\"") && stemmed == null; } }

        public Term(string original, string parsed, string? stemmed, string? sql_parsed, string? sql_stemmed) {
            this.original = original;
            this.parsed = parsed;
            this.stemmed = stemmed;

            // for now, only two variations: the parsed string and the stemmed; since stem is usually
            // shorter (and will be first in the OR statement), include it first
            if (!String.is_empty(sql_stemmed))
                sql.add(sql_stemmed);

            if (!String.is_empty(sql_parsed))
                sql.add(sql_parsed);
        }
    }

    private Geary.SearchQuery.Strategy strategy;

    // Maps of localised search operator names and values to their
    // internal forms
    private static Gee.HashMap<string, string> search_op_names =
        new Gee.HashMap<string, string>();
    private static Gee.ArrayList<string> search_op_to_me_values =
        new Gee.ArrayList<string>();
    private static Gee.ArrayList<string> search_op_from_me_values =
        new Gee.ArrayList<string>();
    private static Gee.HashMap<string, string> search_op_is_values =
        new Gee.HashMap<string, string>();


    static construct {
        // Map of possibly translated search operator names and values
        // to English/internal names and values. We include the
        // English version anyway so that when translations provide a
        // localised version of the operator names but have not also
        // translated the user manual, the English version in the
        // manual still works.

        // Can be typed in the search box like "attachment:file.txt"
        // to find messages with attachments with a particular name.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "attachment"), SEARCH_OP_ATTACHMENT);
        // Can be typed in the search box like
        // "bcc:johndoe@example.com" to find messages bcc'd to a
        // particular person.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "bcc"), SEARCH_OP_BCC);
        // Can be typed in the search box like "body:word" to find
        // "word" only if it occurs in the body of a message.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "body"), SEARCH_OP_BODY);
        // Can be typed in the search box like
        // "cc:johndoe@example.com" to find messages cc'd to a
        // particular person.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "cc"), SEARCH_OP_CC);
        // Can be typed in the search box like
        // "from:johndoe@example.com" to find messages from a
        // particular sender.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "from"), SEARCH_OP_FROM);
        // Can be typed in the search box like "is:unread" to find
        // messages that are read, unread, or starred.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "is"), SEARCH_OP_IS);
        // Can be typed in the search box like "subject:word" to find
        // "word" only if it occurs in the subject of a message.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary
        // User Guide.
        search_op_names.set(C_("Search operator", "subject"), SEARCH_OP_SUBJECT);
        // Can be typed in the search box like
        // "to:johndoe@example.com" to find messages received by a
        // particular person.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_names.set(C_("Search operator", "to"), SEARCH_OP_TO);

        // And the English language versions
        search_op_names.set("attachment", SEARCH_OP_ATTACHMENT);
        search_op_names.set("bcc", SEARCH_OP_BCC);
        search_op_names.set("body", SEARCH_OP_BODY);
        search_op_names.set("cc", SEARCH_OP_CC);
        search_op_names.set("from", SEARCH_OP_FROM);
        search_op_names.set("is", SEARCH_OP_IS);
        search_op_names.set("subject", SEARCH_OP_SUBJECT);
        search_op_names.set("to", SEARCH_OP_TO);

        // Can be typed in the search box after "to:", "cc:" and
        // "bcc:" e.g.: "to:me". Matches conversations that are
        // addressed to the user.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_to_me_values.add(
            C_("Search operator value - mail addressed to the user", "me")
        );
        search_op_to_me_values.add(SEARCH_OP_ADDRESSABLE_VALUE_ME);

        // Can be typed in the search box after "from:" i.e.:
        // "from:me". Matches conversations were sent by the user.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_from_me_values.add(
            C_("Search operator value - mail sent by the user", "me")
        );
        search_op_from_me_values.add(SEARCH_OP_ADDRESSABLE_VALUE_ME);

        // Can be typed in the search box after "is:" i.e.:
        // "is:read". Matches conversations that are flagged as read.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_is_values.set(
            C_("'is:' search operator value", "read"), SEARCH_OP_VALUE_READ
        );
        // Can be typed in the search box after "is:" i.e.:
        // "is:starred". Matches conversations that are flagged as
        // starred.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_is_values.set(
            C_("'is:' search operator value", "starred"), SEARCH_OP_VALUE_STARRED
        );
        // Can be typed in the search box after "is:" i.e.:
        // "is:unread". Matches conversations that are flagged unread.
        //
        // The translated string must be a single word (use '-', '_'
        // or similar to combine words into one), should be short, and
        // also match the translation in "search.page" of the Geary User
        // Guide.
        search_op_is_values.set(
            C_("'is:' search operator value", "unread"), SEARCH_OP_VALUE_UNREAD
        );
        search_op_is_values.set(SEARCH_OP_VALUE_READ, SEARCH_OP_VALUE_READ);
        search_op_is_values.set(SEARCH_OP_VALUE_STARRED, SEARCH_OP_VALUE_STARRED);
        search_op_is_values.set(SEARCH_OP_VALUE_UNREAD, SEARCH_OP_VALUE_UNREAD);
    }


    /**
     * Associated {@link ImapDB.Account}.
     */
    public weak ImapDB.Account account { get; private set; }

    /**
     * Returns whether stemming may be used when exerting the search.
     *
     * Determined by {@link Geary.SearchQuery.Strategy} passed to the
     * constructor.
     */
    public bool allow_stemming { get; private set; }

    /**
     * Minimum length of the term before stemming is allowed.
     *
     * This prevents short words that might be stemmed from being stemmed.
     *
     * Overridden by {@link allow_stemming}. Determined by the {@link
     * Geary.SearchQuery.Strategy} passed to the constructor.
     */
    public int min_term_length_for_stemming { get; private set; }


    /**
     * Maximum difference in lengths between term and stemmed variant.
     *
     * This prevents long words from being stemmed to much shorter
     * words (which creates opportunities for greedy matching).
     *
     * Overridden by {@link allow_stemming}. Determined by the {@link
     * Geary.SearchQuery.Strategy} passed to the constructor.
     */
    public int max_difference_term_stem_lengths { get; private set; }

    /**
     * Maximum difference in lengths between a matched word and the stemmed variant it matched
     * against.
     *
     * This prevents long words being matched to short stem variants (which creates opportunities
     * for greedy matching).
     *
     * Overridden by {@link allow_stemming}. Determined by the {@link
     * Geary.SearchQuery.Strategy} passed to the constructor.
     */
    public int max_difference_match_stem_lengths { get; private set; }

    // Maps search operator field names such as "to", "cc", "is" to
    // their search term values. Note that terms without an operator
    // are stored with null as the key. Not using a MultiMap because
    // we (might) need a guarantee of order.
    private Gee.HashMap<string?, Gee.ArrayList<Term>> field_map
        = new Gee.HashMap<string?, Gee.ArrayList<Term>>();

    // A list of all search terms, regardless of search op field name
    private Gee.ArrayList<Term> all = new Gee.ArrayList<Term>();

    private SnowBall.Stemmer stemmer;


    public async SearchQuery(Geary.Account owner,
                             ImapDB.Account local,
                             Gee.Collection<Geary.SearchQuery.Term> expression,
                             string raw,
                             Geary.SearchQuery.Strategy strategy,
                             GLib.Cancellable? cancellable) {
        base(expression, raw);
        this.account = local;
        this.stemmer = new SnowBall.Stemmer(find_appropriate_search_stemmer());

        switch (strategy) {
            case Strategy.EXACT:
                allow_stemming = false;
                min_term_length_for_stemming = int.MAX;
                max_difference_term_stem_lengths = 0;
                max_difference_match_stem_lengths = 0;
            break;

            case Strategy.CONSERVATIVE:
                allow_stemming = true;
                min_term_length_for_stemming = 6;
                max_difference_term_stem_lengths = 2;
                max_difference_match_stem_lengths = 2;
            break;

            case Strategy.AGGRESSIVE:
                allow_stemming = true;
                min_term_length_for_stemming = 4;
                max_difference_term_stem_lengths = 4;
                max_difference_match_stem_lengths = 3;
            break;

            case Strategy.HORIZON:
                allow_stemming = true;
                min_term_length_for_stemming = 0;
                max_difference_term_stem_lengths = int.MAX;
                max_difference_match_stem_lengths = int.MAX;
            break;
        }

        yield prepare(cancellable);
    }

    public Gee.Collection<string?> get_fields() {
        return field_map.keys;
    }

    public Gee.List<Term>? get_search_terms(string? field) {
        return field_map.has_key(field) ? field_map.get(field) : null;
    }

    public Gee.List<Term>? get_all_terms() {
        return all;
    }

    // For some searches, results are stripped if they're too
    // "greedy", but this requires examining the matched text, which
    // has an expense to fetch, so avoid doing so unless necessary
    internal bool should_strip_greedy_results() {
        // HORIZON strategy is configured in such a way to allow all
        // stemmed variants to match, so don't do any stripping in
        // that case
        //
        // If any of the search terms is exact-match (no prefix
        // matching) or none have stemmed variants, then don't do
        // stripping of "greedy" stemmed matching (because in both
        // cases, there are none)

        bool strip_results = true;
        if (this.strategy == Geary.SearchQuery.Strategy.HORIZON)
            strip_results = false;
        else if (traverse<Term>(this.all).any(
                     term => term.stemmed == null || term.is_exact)) {
            strip_results = false;
        }
        return strip_results;
    }

    internal Gee.Map<Geary.NamedFlag,bool> get_removal_conditions() {
        Gee.Map<Geary.NamedFlag,bool> conditions =
            new Gee.HashMap<Geary.NamedFlag,bool>();
        foreach (string? field in this.field_map.keys) {
            if (field == SEARCH_OP_IS) {
                Gee.List<Term>? terms = get_search_terms(field);
                foreach (Term term in terms)
                    if (term.parsed == SEARCH_OP_VALUE_READ)
                        conditions.set(new NamedFlag("UNREAD"), true);
                    else if (term.parsed == SEARCH_OP_VALUE_UNREAD)
                        conditions.set(new NamedFlag("UNREAD"), false);
                    else if (term.parsed == SEARCH_OP_VALUE_STARRED)
                        conditions.set(new NamedFlag("FLAGGED"), false);
            }
        }
        return conditions;
    }

    // Return a map of column -> phrase, to use as WHERE column MATCH 'phrase'.
    internal Gee.HashMap<string, string> get_query_phrases() {
        Gee.HashMap<string, string> phrases = new Gee.HashMap<string, string>();
        foreach (string? field in field_map.keys) {
            Gee.List<Term>? terms = get_search_terms(field);
            if (terms == null || terms.size == 0 || field == "is")
                continue;

            // Each Term is an AND but the SQL text within in are OR ... this allows for
            // each user term to be AND but the variants of each term are or.  So, if terms are
            // [party] and [eventful] and stems are [parti] and [event], the search would be:
            //
            // (party* OR parti*) AND (eventful* OR event*)
            //
            // Obviously with stemming there's the possibility of the stemmed variant being nothing
            // but a broader search of the original term (such as event* and eventful*) but do both
            // to determine from each hit result which term caused the hit, and if it's too greedy
            // a match of the stemmed variant, it can be stripped from the results.
            //
            // Note that this uses SQLite's "standard" query syntax for MATCH, where AND is implied
            // (and would be treated as search term if included), parentheses are not allowed, and
            // OR has a higher precedence than AND.  So the above example in standard syntax is:
            //
            // party* OR parti* eventful* OR event*
            StringBuilder builder = new StringBuilder();
            foreach (Term term in terms) {
                if (term.sql.size == 0)
                    continue;

                if (term.is_exact) {
                    builder.append_printf("%s ", term.parsed);
                } else {
                    bool is_first_sql = true;
                    foreach (string sql in term.sql) {
                        if (!is_first_sql)
                            builder.append(" OR ");

                        builder.append_printf("%s ", sql);
                        is_first_sql = false;
                    }
                }
            }

            phrases.set(field ?? "MessageSearchTable", builder.str);
        }

        return phrases;
    }

    private async void prepare(GLib.Cancellable? cancellable) {
        // A few goals here:
        //   1) Append an * after every term so it becomes a prefix search
        //      (see <https://www.sqlite.org/fts3.html#section_3>)
        //   2) Strip out common words/operators that might get interpreted as
        //      search operators
        //   3) Parse each word into a list of which field it applies to, so
        //      you can do "to:johndoe@example.com thing" (quotes excluded)
        //      to find messages to John containing the word thing
        // We ignore everything inside quotes to give the user a way to
        // override our algorithm here.  The idea is to offer one search query
        // syntax for Geary that we can use locally and via IMAP, etc.

        string quote_balanced = this.raw;
        if (Geary.String.count_char(this.raw, '"') % 2 != 0) {
            // Remove the last quote if it's not balanced.  This has the
            // benefit of showing decent results as you type a quoted phrase.
            int last_quote = this.raw.last_index_of_char('"');
            assert(last_quote >= 0);
            quote_balanced = this.raw.splice(last_quote, last_quote + 1, " ");
        }

        string[] words = quote_balanced.split_set(" \t\r\n()%*\\");
        bool in_quote = false;
        foreach (string s in words) {
            string? field = null;

            s = s.strip();

            int quotes = Geary.String.count_char(s, '"');
            if (!in_quote && quotes > 0) {
                in_quote = true;
                --quotes;
            }

            Term? term;
            if (in_quote) {
                // HACK: this helps prevent a syntax error when the user types
                // something like from:"somebody".  If we ever properly support
                // quotes after : we can get rid of this.
                term = new Term(s, s, null, s.replace(":", " "), null);
            } else {
                string original = s;

                // Some common search phrases we don't respect and
                // therefore don't want to fall through to search
                // results
                // XXX translate these
                string lower = s.down();
                switch (lower) {
                    case "":
                    case "and":
                    case "or":
                    case "not":
                    case "near":
                        continue;

                    default:
                        if (lower.has_prefix("near/"))
                            continue;
                    break;
                }

                if (s.has_prefix("-"))
                    s = s.substring(1);

                if (s == "")
                    continue;

                // TODO: support quotes after :
                string[] parts = s.split(":", 2);
                if (parts.length > 1)
                    field = extract_field_from_token(parts, ref s);

                if (field == SEARCH_OP_IS) {
                    // s will have been de-translated
                    term = new Term(original, s, null, null, null);
                } else {
                    // SQL MATCH syntax for parsed term
                    string? sql_s = "%s*".printf(s);

                    // stem the word, but if stemmed and stem is
                    // simply shorter version of original term, only
                    // prefix-match search for it (i.e. avoid
                    // searching for [archive* OR archiv*] when that's
                    // the same as [archiv*]), otherwise search for
                    // both
                    string? stemmed = yield stem_search_term(s, cancellable);

                    string? sql_stemmed = null;
                    if (stemmed != null) {
                        sql_stemmed = "%s*".printf(stemmed);
                        if (s.has_prefix(stemmed))
                            sql_s = null;
                    }

                    // if term contains continuation characters, treat
                    // as exact search to reduce effects of tokenizer
                    // splitting terms w/ punctuation in them
                    if (String.contains_any_char(s, SEARCH_TERM_CONTINUATION_CHARS))
                        s = "\"%s\"".printf(s);

                    term = new Term(original, s, stemmed, sql_s, sql_stemmed);
                }
            }

            if (in_quote && quotes % 2 != 0)
                in_quote = false;

            // Finally, add the term
            if (!this.field_map.has_key(field)) {
                this.field_map.set(field, new Gee.ArrayList<Term>());
            }
            this.field_map.get(field).add(term);
            this.all.add(term);
        }
    }

    private string? extract_field_from_token(string[] parts, ref string token) {
        string? field = null;
        if (Geary.String.is_empty_or_whitespace(parts[1])) {
            // User stopped at "field:", treat it as if they hadn't
            // typed the ':'
            token = parts[0];
        } else {
            field = search_op_names.get(parts[0].down());
            if (field == SEARCH_OP_IS) {
                string? value = search_op_is_values.get(parts[1].down());
                if (value != null) {
                    token = value;
                } else {
                    // Unknown op value, pretend there is no search op
                    field = null;
                }
            } else if (field == SEARCH_OP_FROM &&
                       parts[1].down() in search_op_from_me_values) {
                // Search for all addresses on the account. Bug 768779
                token = this.account.account_information.primary_mailbox.address;
            } else if (field in SEARCH_OP_TO_ME_FIELDS &&
                       parts[1].down() in search_op_to_me_values) {
                // Search for all addresses on the account. Bug 768779
                token = this.account.account_information.primary_mailbox.address;
            } else if (field != null) {
                token = parts[1];
            }
        }
        return field;
    }

    /**
     * Converts unquoted search terms into a stemmed search term.
     *
     * Prior experience with the Snowball stemmer indicates it is too
     * aggressive for our tastes when coupled with prefix-matching of
     * all unquoted terms (see
     * https://bugzilla.gnome.org/show_bug.cgi?id=713179).
     *
     * This method is part of a larger strategy designed to dampen
     * that aggressiveness without losing the benefits of stemming
     * entirely: The database's FTS table uses no stemming, but
     * libstemmer is used to generate stemmed search terms.
     * Post-search processing is then to strip results which are too
     * "greedy" due to prefix-matching the stemmed variant.
     *
     * Some heuristics are in place simply to determine if stemming should occur:
     *
     * # If stemming is unallowed, no stemming occurs.
     * # If the term is < min. term length for stemming, no stemming occurs.
     * # If the stemmer returns a stem that is the same as the original term, no stemming occurs.
     * # If the difference between the stemmed word and the original term is more than
     *   maximum allowed, no stemming occurs.  This works under the assumption that if
     *   the user has typed a long word, they do not want to "go back" to searching for a much
     *   shorter version of it.  (For example, "accountancies" stems to "account").
     *
     * Otherwise, the stem for the term is returned.
     */
    private async string? stem_search_term(string term,
                                           GLib.Cancellable? cancellable) {
        if (!this.allow_stemming)
            return null;

        int term_length = term.length;
        if (term_length < this.min_term_length_for_stemming)
            return null;

        string? stemmed = this.stemmer.stem(term, term.length);
        if (String.is_empty(stemmed)) {
            debug("Empty stemmed term returned for \"%s\"", term);
            return null;
        }

        // If same term returned, treat as non-stemmed
        if (stemmed == term)
            return null;

        // Don't search for stemmed words that are significantly shorter than the user's search term
        if (term_length - stemmed.length > this.max_difference_term_stem_lengths) {
            debug("Stemmed \"%s\" dropped searching for \"%s\": too much distance in terms",
                stemmed, term);

            return null;
        }

        debug("Search processing: term -> stem is \"%s\" -> \"%s\"", term, stemmed);
        return stemmed;
    }

    private string find_appropriate_search_stemmer() {
        // Unfortunately, the stemmer library only accepts the full language
        // name for the stemming algorithm.  This translates between the user's
        // preferred language ISO 639-1 code and our available stemmers.
        // FIXME: the available list here is determined by what's included in
        // src/sqlite3-unicodesn/CMakeLists.txt.  We should pass that list in
        // instead of hardcoding it here.
        foreach (string l in Intl.get_language_names()) {
            switch (l) {
                case "ar": return "arabic";
                case "eu": return "basque";
                case "ca": return "catalan";
                case "da": return "danish";
                case "nl": return "dutch";
                case "en": return "english";
                case "fi": return "finnish";
                case "fr": return "french";
                case "de": return "german";
                case "el": return "greek";
                case "hi": return "hindi";
                case "hu": return "hungarian";
                case "id": return "indonesian";
                case "ga": return "irish";
                case "it": return "italian";
                case "lt": return "lithuanian";
                case "ne": return "nepali";
                case "no": return "norwegian";
                case "pt": return "portuguese";
                case "ro": return "romanian";
                case "ru": return "russian";
                case "sr": return "serbian";
                case "es": return "spanish";
                case "sv": return "swedish";
                case "ta": return "tamil";
                case "tr": return "turkish";
            }
        }

        // Default to English because it seems to be on average the language
        // most likely to be present in emails, regardless of the user's
        // language setting.  This is not an exact science, and search results
        // should be ok either way in most cases.
        return "english";
    }

}
