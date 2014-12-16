/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Various associated state with a single term in a {@link ImapDB.SearchQuery}.
 */

private class Geary.ImapDB.SearchTerm : BaseObject {
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
    
    public SearchTerm(string original, string parsed, string? stemmed, string? sql_parsed, string? sql_stemmed) {
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

