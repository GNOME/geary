/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An object to hold state for various search subsystems that might need to
 * parse the same text string different ways.  The only interaction the API
 * user should have with this is creating new ones and then passing them off to
 * the search methods in the engine.
 *
 * TODO: support anything other than ImapDB.Account's search methods.
 */
public class Geary.SearchQuery : BaseObject {
    public string raw { get; private set; }
    public bool parsed { get; internal set; default = false; }
    
    // Not using a MultiMap because we (might) need a guarantee of order.
    private Gee.HashMap<string?, Gee.ArrayList<string>> field_map
        = new Gee.HashMap<string?, Gee.ArrayList<string>>();
    
    public SearchQuery(string query) {
        raw = query;
    }
    
    internal void add_token(string? field, string token) {
        if (!field_map.has_key(field))
            field_map.set(field, new Gee.ArrayList<string>());
        
        field_map.get(field).add(token);
    }
    
    internal Gee.Collection<string?> get_fields() {
        return field_map.keys;
    }
    
    internal Gee.List<string>? get_tokens(string? field) {
        if (!field_map.has_key(field))
            return null;
        
        return field_map.get(field);
    }
}
