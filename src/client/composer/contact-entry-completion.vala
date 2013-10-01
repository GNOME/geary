/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ContactEntryCompletion : Gtk.EntryCompletion {
    private ContactListStore list_store;
    private Gtk.TreeIter? last_iter = null;
    
    public ContactEntryCompletion(ContactListStore list_store) {
        this.list_store = list_store;
        
        model = list_store;
        set_match_func(completion_match_func);
        
        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        pack_start(text_renderer, true);
        add_attribute(text_renderer, "markup", ContactListStore.Column.CONTACT_MARKUP_NAME);
        
        set_inline_selection(true);
        match_selected.connect(on_match_selected);
        cursor_on_match.connect(on_cursor_on_match);
    }
    
    private bool on_match_selected(Gtk.EntryCompletion sender, Gtk.TreeModel model, Gtk.TreeIter iter) {
        string full_address = list_store.get_full_address(iter);
            
        Gtk.Entry? entry = sender.get_entry() as Gtk.Entry;
        if (entry == null)
            return false;
        
        int current_address_index;
        string current_address_remainder;
        Gee.List<string> addresses = get_addresses(sender, out current_address_index, null,
            out current_address_remainder);
        addresses[current_address_index] = full_address;
        if (!Geary.String.is_empty_or_whitespace(current_address_remainder))
            addresses.insert(current_address_index + 1, current_address_remainder);
        string delimiter = ", ";
        entry.text = concat_strings(addresses, delimiter);
        
        int characters_seen_so_far = 0;
        for (int i = 0; i <= current_address_index; i++)
            characters_seen_so_far += addresses[i].char_count() + delimiter.char_count();
        
        entry.set_position(characters_seen_so_far);
        
        return true;
    }
    
    private bool on_cursor_on_match(Gtk.EntryCompletion sender, Gtk.TreeModel model, Gtk.TreeIter iter) {
        last_iter = iter;
        return true;
    }
    
    public void trigger_selection() {
        if (last_iter != null) {
            on_match_selected(this, model, last_iter);
            last_iter = null;
        }
    }
    
    public void reset_selection() {
        last_iter = null;
    }
    
    private bool completion_match_func(Gtk.EntryCompletion completion, string key, Gtk.TreeIter iter) {
        // We don't use the provided key, because the user can enter multiple addresses.
        int current_address_index;
        string current_address_key;
        get_addresses(completion, out current_address_index, out current_address_key);
        
        Geary.Contact? contact = list_store.get_contact(iter);
        if (contact == null)
            return false;
        
        string highlighted_result;
        if (!match_prefix_contact(current_address_key, contact, out highlighted_result))
            return false;
        
        list_store.set_highlighted_result(iter, highlighted_result, current_address_key);
        
        return true;
    }
    
    private Gee.List<string> get_addresses(Gtk.EntryCompletion completion,
        out int current_address_index = null, out string current_address_key = null,
        out string current_address_remainder = null) {
        current_address_index = 0;
        current_address_key = "";
        current_address_remainder = "";
        Gtk.Entry? entry = completion.get_entry() as Gtk.Entry;
        Gee.List<string> empty_addresses = new Gee.ArrayList<string>();
        empty_addresses.add("");
        if (entry == null)
            return empty_addresses;
        
        string? original_text = entry.get_text();
        if (original_text == null)
            return empty_addresses;
        
        int cursor_position = entry.cursor_position;
        int cursor_offset = original_text.index_of_nth_char(cursor_position);
        if (cursor_offset < 0)
            return empty_addresses;
        
        Gee.List<string> addresses = new Gee.ArrayList<string>();
        string delimiter = ",";
        string[] addresses_array = original_text.split(delimiter);
        foreach (string address in addresses_array)
            addresses.add(address);
        
        if (addresses.size < 1)
            return empty_addresses;
        
        int bytes_seen_so_far = 0;
        current_address_index = addresses.size - 1;
        for (int i = 0; i < addresses.size; i++) {
            int token_bytes = addresses[i].length + delimiter.length;
            if ((bytes_seen_so_far + token_bytes) > cursor_offset) {
                current_address_index = i;
                current_address_key = addresses[i]
                    .substring(0, cursor_offset - bytes_seen_so_far)
                    .strip().normalize().casefold();
                
                current_address_remainder = addresses[i]
                    .substring(cursor_offset - bytes_seen_so_far).strip();
                break;
            }
            bytes_seen_so_far += token_bytes;
        }
        
        return addresses;
    }
    
    // We could only add the delimiter *between* each string (i.e., don't add it after the last
    // string). But it's easier for the user if they don't have to manually type a comma after
    // adding each address. So we add the delimiter after every string.
    private string concat_strings(Gee.List<string> strings, string delimiter) {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < strings.size; i++) {
            builder.append(strings[i]);
            builder.append(delimiter);
        }
        
        return builder.str;
    }
    
    private bool match_prefix_contact(string needle, Geary.Contact contact,
        out string highlighted_result = null) {
        string email_result;
        bool email_match = match_prefix_string(needle, contact.email, out email_result);
        
        string real_name_result;
        bool real_name_match = match_prefix_string(needle, contact.real_name, out real_name_result);
        
        // email_result and real_name_result were already escaped, then <b></b> tags were added to
        // highlight matches. We don't want to escape them again.
        highlighted_result = contact.real_name == null ? email_result :
            real_name_result + Markup.escape_text(" <") + email_result + Markup.escape_text(">");
        
        return email_match || real_name_match;
    }

    private bool match_prefix_string(string needle, string? haystack = null,
        out string highlighted_result = null) {
        highlighted_result = "";
        
        if (Geary.String.is_empty(haystack) || Geary.String.is_empty(needle))
            return false;
        
        // Default result if there is no match or we encounter an error.
        highlighted_result = haystack;
        
        bool matched = false;
        try {
            string escaped_needle = Regex.escape_string(needle.normalize());
            Regex regex = new Regex("\\b" + escaped_needle, RegexCompileFlags.CASELESS);
            string haystack_normalized = haystack.normalize();
            if (regex.match(haystack_normalized)) {
                highlighted_result = regex.replace_eval(haystack_normalized, -1, 0, 0, eval_callback);
                matched = true;
            }
        } catch (RegexError err) {
            debug("Error matching regex: %s", err.message);
        }
        
        highlighted_result = Markup.escape_text(highlighted_result)
            .replace("&#x91;", "<b>").replace("&#x92;", "</b>");
        
        return matched;
    }

    private bool eval_callback(MatchInfo match_info, StringBuilder result) {
        string? match = match_info.fetch(0);
        if (match != null) {
            result.append("\xc2\x91%s\xc2\x92".printf(match));
            // This is UTF-8 encoding of U+0091 and U+0092
        }
        
        return false;
    }
}

