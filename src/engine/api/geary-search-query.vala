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


    /** The account that owns this query. */
    public Account owner { get; private set; }

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
                          string raw,
                          Strategy strategy) {
        this.owner = owner;
        this.raw = raw;
        this.strategy = strategy;
    }

    public string to_string() {
        return "\"%s\" (%s)".printf(this.raw, this.strategy.to_string());
    }
}

