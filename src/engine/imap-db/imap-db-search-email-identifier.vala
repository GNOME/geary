/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.SearchEmailIdentifier : ImapDB.EmailIdentifier,
    Gee.Comparable<SearchEmailIdentifier> {
    public static int compare_descending(SearchEmailIdentifier a, SearchEmailIdentifier b) {
        return b.compare_to(a);
    }
    
    public DateTime? date_received { get; private set; }
    
    public SearchEmailIdentifier(int64 message_id, DateTime? date_received) {
        base(message_id, null);
        
        this.date_received = date_received;
    }
    
    public override int natural_sort_comparator(Geary.EmailIdentifier o) {
        ImapDB.SearchEmailIdentifier? other = o as ImapDB.SearchEmailIdentifier;
        if (other == null)
            return 1;
        
        return compare_to(other);
    }
    
    public virtual int compare_to(SearchEmailIdentifier other) {
        if (date_received != null && other.date_received != null)
            return date_received.compare(other.date_received);
        if (date_received == null && other.date_received == null)
            return stable_sort_comparator(other);
        
        return (date_received == null ? -1 : 1);
    }
    
    public override string to_string() {
        return "[%s/null/%s]".printf(message_id.to_string(),
            (date_received == null ? "null" : date_received.to_string()));
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
}
