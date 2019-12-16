/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.met>
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
 * @see Account.new_search_query
 * @see Account.local_search_async
 * @see Account.get_search_matches_async
 * @see App.SearchFolder.search
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
        HORIZON
    }


    /**
     * Base class for search term operators.
     */
    public abstract class Operator : BaseObject {

        /** Returns a string representation, for debugging. */
        public abstract string to_string();

    }

    /**
     * Conjunction search operator, true if all operands are true.
     */
    public class AndOperator : Operator {


        private Gee.Collection<Operator> operands;


        public AndOperator(Gee.Collection<Operator> operands) {
            this.operands = operands;
        }

        public Gee.Collection<Operator> get_operands() {
            return this.operands.read_only_view;
        }

        public override string to_string() {
            var builder = new GLib.StringBuilder("AND(");
            var iter = this.operands.iterator();
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
     * Disjunction search operator, true if any operands are true.
     */
    public class OrOperator : Operator {


        private Gee.Collection<Operator> operands;


        public OrOperator(Gee.Collection<Operator> operands) {
            this.operands = operands;
        }

        public Gee.Collection<Operator> get_operands() {
            return this.operands.read_only_view;
        }

        public override string to_string() {
            var builder = new GLib.StringBuilder("OR(");
            var iter = this.operands.iterator();
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
     * Negation search operator, true if the operand is false.
     */
    public class NotOperator : Operator {


        private Operator operand;


        public NotOperator(Operator operand) {
            this.operand = operand;
        }

        public override string to_string() {
            return "NOT(%s)".printf(operand.to_string());
        }

    }

    /**
     * Text email property operator, true if it matches the given term.
     */
    public class TextOperator : Operator {


        /**
         * Supported text email properties that can be queried.
         *
         * @see TextOperator
         */
        public enum Property {
            /** Search for a term in all supported properties. */
            ALL,

            /** Search for a term in the To field. */
            TO,

            /** Search for a term in the Bcc field. */
            BCC,

            /** Search for a term in the Cc field. */
            CC,

            /** Search for a term in the From field. */
            FROM,

            /** Search for a term in the email subject. */
            SUBJECT,

            /** Search for a term in the email body. */
            BODY,

            /** Search for a term in email attachment names. */
            ATTACHMENT_NAME;
        }


        public Property target { get; private set; }
        public Strategy matching_strategy { get; private set; }
        public string term { get; private set; }


        public TextOperator(Property target,
                            Strategy matching_strategy,
                            string term) {
            this.target = target;
            this.matching_strategy = matching_strategy;
            this.term = term;
        }

        public override string to_string() {
            return "%s:%s(%s)".printf(
                ObjectUtils.to_enum_nick(typeof(Property), this.target).up(),
                ObjectUtils.to_enum_nick(typeof(Strategy), this.target).up(),
                this.term
            );
        }

    }


    /**
     * Boolean email property operator, true if it matches the given value.
     */
    public class BooleanOperator : Operator {


        /**
         * Supported Boolean email properties that can be queried.
         *
         * @see BooleanOperator
         */
        public enum Property {
            /** If the email is unread. */
            IS_UNREAD,

            /** If the email is flagged. */
            IS_FLAGGED;

        }


        public Property target { get; private set; }
        public bool value { get; private set; }


        public BooleanOperator(Property target, bool value) {
            this.target = target;
            this.value = value;
        }

        public override string to_string() {
            return "%s(%s)".printf(
                ObjectUtils.to_enum_nick(typeof(Property), this.target).up(),
                this.value.to_string()
            );
        }

    }


    /** The account that owns this query. */
    public Account owner { get; private set; }

    /**
     * The search expression to be evaluated.
     */
    public Operator expression { get; private set; }

    /**
     * The original search text.
     *
     * This is used mostly for debugging.
     */
    public string raw { get; private set; }

    /**
     * The selected {@link Strategy} quality.
     */
    public Strategy strategy { get; private set; }


    protected SearchQuery(Account owner,
                          Operator expression,
                          string raw,
                          Strategy strategy) {
        this.owner = owner;
        this.expression = expression;
        this.raw = raw;
        this.strategy = strategy;
    }

    public string to_string() {
        return "\"%s\" (%s)".printf(this.raw, this.expression.to_string());
    }

}
