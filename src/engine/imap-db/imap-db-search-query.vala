/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Internal implementation of {@link Geary.SearchQuery}.
 */

private class Geary.ImapDB.SearchQuery : Geary.SearchQuery {
    /**
     * Associated {@link ImapDB.Account}.
     */
    public weak ImapDB.Account account { get; private set; }
    
    /**
     * Whether or not the query has been parsed and processed prior to search submission.
     */
    public bool parsed { get; set; default = false; }
    
    /**
     * Determined by {@link strategy}.
     */
    public bool allow_stemming { get; private set; }
    
    /**
     * Minimum length of the term before stemming is allowed.
     *
     * This prevents short words that might be stemmed from being stemmed.
     *
     * Overridden by {@link allow_stemming}.  Determined by {@link strategy}.
     */
    public int min_term_length_for_stemming { get; private set; }
    
    /**
     * Maximum difference in lengths between term and stemmed variant.
     *
     * This prevents long words from being stemmed to much shorter words (which creates
     * opportunities for greedy matching).
     *
     * Overridden by {@link allow_stemming}.  Determined by {@link strategy}.
     */
    public int max_difference_term_stem_lengths { get; private set; }
    
    /**
     * Maximum difference in lengths between a matched word and the stemmed variant it matched
     * against.
     *
     * This prevents long words being matched to short stem variants (which creates opportunities
     * for greedy matching).
     *
     * Overridden by {@link allow_stemming}.  Determined by {@link strategy}.
     */
    public int max_difference_match_stem_lengths { get; private set; }
    
    // Not using a MultiMap because we (might) need a guarantee of order.
    private Gee.HashMap<string?, Gee.ArrayList<SearchTerm>> field_map
        = new Gee.HashMap<string?, Gee.ArrayList<SearchTerm>>();
    private Gee.ArrayList<SearchTerm> all = new Gee.ArrayList<SearchTerm>();
    
    public SearchQuery(ImapDB.Account account, string query, Geary.SearchQuery.Strategy strategy) {
        base (query, strategy);
        
        this.account = account;
        
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
            
            default:
                assert_not_reached();
        }
    }
    
    public void add_search_term(string? field, SearchTerm term) {
        if (!field_map.has_key(field))
            field_map.set(field, new Gee.ArrayList<SearchTerm>());
        
        field_map.get(field).add(term);
        all.add(term);
    }
    
    public Gee.Collection<string?> get_fields() {
        return field_map.keys;
    }
    
    public Gee.List<SearchTerm>? get_search_terms(string? field) {
        return field_map.has_key(field) ? field_map.get(field) : null;
    }
    
    public Gee.List<SearchTerm>? get_all_terms() {
        return all;
    }
}

