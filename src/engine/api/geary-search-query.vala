/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.met>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Specifies an expression for searching email in a search folder.
 *
 * New instances can be constructed via {@link
 * Account.new_search_query} and then passed to search methods on
 * {@link Account} or {@link App.SearchFolder}.
 *
 * Actual search queries are specified by the given {@link
 * expression}, which is a list of {@link Term}. The expression
 * denotes the conjunction of all given terms, that is, each term is
 * combined by a Boolean AND function. While the order of the terms is
 * not important, the expression should attempt to reflect the
 * free-text search query it was built from (if any). A more
 * expressive language is not supported since it is designed to work
 * with both the Engine's built-in full text search system as well as
 * other server-based systems, including IMAP.
 *
 * @see Account.new_search_query
 * @see Account.local_search_async
 * @see Account.get_search_matches_async
 * @see App.SearchFolder.update_query
 */

public abstract class Geary.SearchQuery : BaseObject {


    /**
     * An advisory parameter regarding search quality, scope, and breadth.
     *
     * The Engine can perform searches based on (unspecified, uncontracted) textual variations of
     * a query's search terms.  Some of those variations may produce undesirable results due to
     * "greedy" matching of terms.  The Strategy parameter allows for an advisory to the Engine
     * about how to use those textual variants, if any at all.
     *
     * This may be respected or ignored by the Engine.  In particular, there's no guarantee it will
     * have any effect on server search.
     */
    public enum Strategy {
        /**
         * Only return exact matches, perform no searches for textual variants.
         *
         * Note that Geary's search syntax does prefix-matching for unquoted strings.  EXACT means
         * exact ''prefix-''matching in this case.
         */
        EXACT,
        /**
         * Allow for searching for a small set of textual variants and small differences in search
         * terms.  This is a good default.
         */
        CONSERVATIVE,
        /**
         * Allow for searching for a broad set of textual variants and larger differences in
         * search terms.
         */
        AGGRESSIVE,
        /**
         * Search for all textual variants, i.e. "the sky's the limit."
         */
        HORIZON;


        /** Determines if stemming may be used for an operator. */
        internal bool is_stemming_enabled() {
            return this != EXACT;
        }

        /**
         * The minimum term length before stemming is allowed.
         *
         * This prevents short words that might be stemmed from being stemmed.
         */
        internal int get_min_term_length_for_stemming() {
            var min = 0;
            switch (this) {
            case EXACT:
                min = int.MAX;
                break;
            case CONSERVATIVE:
                min = 6;
                break;
            case AGGRESSIVE:
                min = 4;
                break;
            case HORIZON:
                min = 0;
                break;
            }
            return min;
        }

        /**
         * Maximum difference in lengths between term and stemmed variant.
         *
         * This prevents long words from being stemmed to much shorter
         * words (which creates opportunities for greedy matching).
         */
        internal int get_max_difference_term_stem_lengths() {
            var max = 0;
            switch (this) {
            case EXACT:
                max = 0;
                break;
            case CONSERVATIVE:
                max = 2;
                break;
            case AGGRESSIVE:
                max = 4;
                break;
            case HORIZON:
                max =int.MAX;
                break;
            }
            return max;
        }

    }


    /**
     * Parent class for terms that make up a search query's expression.
     *
     * @see SearchQuery.expression
     */
    public abstract class Term : BaseObject {

        /** Determines opposite of the term is matched. */
        public bool is_negated { get; set; default = false; }

        /** Determines if this term is equal to another. */
        public virtual bool equal_to(Term other) {
            return (
                this.is_negated == other.is_negated &&
                this.get_type() == other.get_type()
            );
        }

        /** Returns a string representation, for debugging. */
        public abstract string to_string();

    }

    /**
     * A term that matches text properties of an email.
     */
    public class EmailTextTerm : Term {


        /**
         * Supported text email properties that can be queried.
         *
         * @see EmailTextTerm
         */
        public enum Property {
            /** Search for a term in all supported properties. */
            ALL,

            /** Search for a term in the To field. */
            TO,

            /** Search for a term in the Cc field. */
            CC,

            /** Search for a term in the Bcc field. */
            BCC,

            /** Search for a term in the From field. */
            FROM,

            /** Search for a term in the email subject. */
            SUBJECT,

            /** Search for a term in the email body. */
            BODY,

            /** Search for a term in email attachment names. */
            ATTACHMENT_NAME;
        }


        /** The email property this term applies to. */
        public Property target { get; private set; }

        /** The strategy used for matching the given terms. */
        public Strategy matching_strategy { get; private set; }

        /**
         * The strings to match against the given target.
         *
         * If more than one term is given, they are treated as the
         * disjunction of all, that is they are combined using the
         * Boolean OR function.
         */
        public Gee.List<string> terms {
            get; private set; default = new Gee.ArrayList<string>();
        }


        public EmailTextTerm(Property target,
                             Strategy matching_strategy,
                             string term) {
            this.target = target;
            this.matching_strategy = matching_strategy;
            this.terms.add(term);
        }

        public EmailTextTerm.disjunction(Property target,
                                         Strategy matching_strategy,
                                         Gee.List<string> terms) {
            this.target = target;
            this.matching_strategy = matching_strategy;
            this.terms.add_all(terms);
        }

        public override bool equal_to(Term other) {
            if (this == other) {
                return true;
            }
            if (!base.equal_to(other)) {
                return false;
            }
            var text = (EmailTextTerm) other;
            if (this.target != text.target ||
                this.matching_strategy != text.matching_strategy ||
                this.terms.size != text.terms.size) {
                return false;
            }
            for (int i = 0; i < this.terms.size; i++) {
                if (this.terms[i] != text.terms[i]) {
                    return false;
                }
            }
            return true;
        }

        public override string to_string() {
            var builder = new GLib.StringBuilder();
            if (this.is_negated) {
                builder.append_c('!');
            }

            builder.append(
                ObjectUtils.to_enum_nick(
                    typeof(Property), this.target).up()
            );
            builder.append_c(':');
            builder.append(
                ObjectUtils.to_enum_nick(
                    typeof(Strategy), this.matching_strategy
                ).up()
            );
            builder.append_c('(');

            var iter = this.terms.iterator();
            if (iter.next()) {
                builder.append(iter.get().to_string());
            }
            while (iter.next()) {
                builder.append_c(',');
                builder.append(iter.get().to_string());
            }
            builder.append_c(')');
            return builder.str;
        }

    }


    /**
     * A term that matches a given flag in an email.
     */
    public class EmailFlagTerm : Term {


        public NamedFlag value { get; private set; }


        public EmailFlagTerm(NamedFlag value) {
            this.value = value;
        }

        public override bool equal_to(Term other) {
            if (this == other) {
                return true;
            }
            if (!base.equal_to(other)) {
                return false;
            }
            return this.value.equal_to(((EmailFlagTerm) other).value);
        }

        public override string to_string() {
            return "%s(%s)".printf(
                this.is_negated ? "!" : "",
                this.value.to_string()
            );
        }

    }


    /**
     * A read-only list of search terms to be evaluated.
     *
     * Each given term is used in a conjunction, that is combined
     * using a Boolean `AND` operator.
     */
    public Gee.List<Term> expression { get; private set; }
    private Gee.List<Term> _rw_expression = new Gee.ArrayList<Term>();

    /**
     * The original search text, if any.
     *
     * This is used mostly for debugging.
     */
    public string raw { get; private set; }


    protected SearchQuery(Gee.Collection<Term> expression,
                          string raw) {
        this._rw_expression.add_all(expression);
        this.expression = this._rw_expression.read_only_view;
        this.raw = raw;
    }

    /** Determines if this query's expression is equal to another's. */
    public bool equal_to(SearchQuery other) {
        if (this == other) {
            return true;
        }
        if (this.expression.size != other.expression.size) {
            return false;
        }
        for (int i = 0; i < this.expression.size; i++) {
            if (!this.expression[i].equal_to(other.expression[i])) {
                return false;
            }
        }
        return true;
    }

    /** Returns a string representation of this query, for debugging. */
    public string to_string() {
        var builder = new GLib.StringBuilder();
        builder.append_printf("\"%s\": ", this.raw);

        var iter = this.expression.iterator();
        if (iter.next()) {
            builder.append(iter.get().to_string());
        }
        while (iter.next()) {
            builder.append_c(',');
            builder.append(iter.get().to_string());
        }
        return builder.str;
    }

}
