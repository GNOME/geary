/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.SearchEmailIdentifier : ImapDB.EmailIdentifier,
    Gee.Comparable<SearchEmailIdentifier> {
    public DateTime? date_received { get; private set; }
    
    public SearchEmailIdentifier(int64 message_id, DateTime? date_received) {
        base(message_id, null);
        
        this.date_received = date_received;
    }
    
    public static int compare_descending(SearchEmailIdentifier a, SearchEmailIdentifier b) {
        return b.compare_to(a);
    }
    
    public static Gee.ArrayList<SearchEmailIdentifier> array_list_from_results(
        Gee.Collection<Geary.EmailIdentifier>? results) {
        Gee.ArrayList<SearchEmailIdentifier> r = new Gee.ArrayList<SearchEmailIdentifier>();
        
        if (results != null) {
            foreach (Geary.EmailIdentifier id in results) {
                SearchEmailIdentifier? search_id = id as SearchEmailIdentifier;
                
                assert(search_id != null);
                r.add(search_id);
            }
        }
        
        return r;
    }
    
    // Searches for a generic EmailIdentifier in a collection of SearchEmailIdentifiers.
    public static SearchEmailIdentifier? collection_get_email_identifier(
        Gee.Collection<SearchEmailIdentifier> collection, Geary.EmailIdentifier id) {
        foreach (SearchEmailIdentifier search_id in collection) {
            if (id.equal_to(search_id))
                return search_id;
        }
        return null;
    }
    
    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        ImapDB.SearchEmailIdentifier? other = o as ImapDB.SearchEmailIdentifier;
        if (other == null)
            return 1;
        
        return compare_to(other);
    }
    
    public virtual int compare_to(SearchEmailIdentifier other) {
        // if both have date received, compare on that, using stable sort if the same
        if (date_received != null && other.date_received != null) {
            int compare = date_received.compare(other.date_received);
            
            return (compare != 0) ? compare : stable_sort_comparator(other);
        }
        
        // if neither have date received, fall back on stable sort
        if (date_received == null && other.date_received == null)
            return stable_sort_comparator(other);
        
        // put identifiers with no date ahead of those with
        return (date_received == null ? -1 : 1);
    }
    
    public override string to_string() {
        return "[%s/null/%s]".printf(message_id.to_string(),
            (date_received == null ? "null" : date_received.to_string()));
    }
}
