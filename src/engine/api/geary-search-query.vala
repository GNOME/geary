/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An object to hold state for various search subsystems that might need to
 * parse the same text string different ways.
 *
 * The only interaction the API user should have with this is creating new ones and then passing
 * them to the search methods in the Engine.
 *
 * @see Geary.Account.open_search
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
     * The original user search text.
     */
    public string raw { get; private set; }
    
    /**
     * The selected {@link Strategy} quality.
     */
    public Strategy strategy { get; private set; }
    
    protected SearchQuery(string raw, Strategy strategy) {
        this.raw = raw;
        this.strategy = strategy;
    }
}

