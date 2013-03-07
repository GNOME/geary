/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class ContactEntryCompletion : Gtk.EntryCompletion {
    // Sort column indices.
    private const int SORT_COLUMN = 0;
    
    private Gtk.ListStore list_store;
    
    private Gtk.TreeIter? last_iter = null;
    
    private enum Column {
        CONTACT_OBJECT,
        CONTACT_MARKUP_NAME,
        LAST_KEY;
        
        public static Type[] get_types() {
            return {
                typeof (Geary.Contact), // CONTACT_OBJECT
                typeof (string),        // CONTACT_MARKUP_NAME
                typeof (string)         // LAST_KEY
            };
        }
    }
    
    public ContactEntryCompletion(Geary.ContactStore? contact_store) {
        list_store = new Gtk.ListStore.newv(Column.get_types());
        list_store.set_sort_func(SORT_COLUMN, sort_func);
        list_store.set_sort_column_id(SORT_COLUMN, Gtk.SortType.ASCENDING);
        
        if (contact_store == null)
            return;
        
        foreach (Geary.Contact contact in contact_store.contacts)
            add_contact(contact);
        
        contact_store.contact_added.connect(on_contact_added);
        contact_store.contact_updated.connect(on_contact_updated);
        
        model = list_store;
        set_match_func(completion_match_func);
        
        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        pack_start(text_renderer, true);
        add_attribute(text_renderer, "markup", Column.CONTACT_MARKUP_NAME);
        
        set_inline_selection(true);
        match_selected.connect(on_match_selected);
        cursor_on_match.connect(on_cursor_on_match);
    }
    
    private void add_contact(Geary.Contact contact) {
        string full_address = contact.get_rfc822_address().get_full_address();
        Gtk.TreeIter iter;
        list_store.append(out iter);
        list_store.set(iter,
            Column.CONTACT_OBJECT, contact,
            Column.CONTACT_MARKUP_NAME, Markup.escape_text(full_address),
            Column.LAST_KEY, "");
    }
    
    private void update_contact(Geary.Contact updated_contact) {
        Gtk.TreeIter iter;
        if (!list_store.get_iter_first(out iter))
            return;
        
        do {
            if (get_contact(iter) != updated_contact)
                continue;
            
            Gtk.TreePath? path = list_store.get_path(iter);
            if (path != null)
                list_store.row_changed(path, iter);
            
            return;
        } while (list_store.iter_next(ref iter));
    }
    
    private void on_contact_added(Geary.Contact contact) {
        add_contact(contact);
    }
    
    private void on_contact_updated(Geary.Contact contact) {
        update_contact(contact);
    }
    
    private bool on_match_selected(Gtk.EntryCompletion sender, Gtk.TreeModel model, Gtk.TreeIter iter) {
        string? full_address = get_full_address(iter);
        if (full_address == null)
            return false;
            
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
    
    private Geary.Contact? get_contact(Gtk.TreeIter iter) {
        GLib.Value contact_value;
        list_store.get_value(iter, Column.CONTACT_OBJECT, out contact_value);
        return contact_value.get_object() as Geary.Contact;
    }
    
    private string? get_full_address(Gtk.TreeIter iter) {
        Geary.Contact? contact = get_contact(iter);
        return contact == null ? null : contact.get_rfc822_address().to_rfc822_string();
    }
    
    private bool completion_match_func(Gtk.EntryCompletion completion, string key, Gtk.TreeIter iter) {
        // We don't use the provided key, because the user can enter multiple addresses.
        int current_address_index;
        string current_address_key;
        get_addresses(completion, out current_address_index, out current_address_key);
        
        Geary.Contact? contact = get_contact(iter);
        if (contact == null)
            return false;
        
        string highlighted_result;
        if (!match_prefix_contact(current_address_key, contact, out highlighted_result))
            return false;
            
        // Changing a row in the list store causes Gtk.EntryCompletion to re-evaluate
        // completion_match_func for that row. Thus we need to make sure the key has
        // actually changed before settings the highlighting--otherwise we will cause
        // an infinite loop.
        GLib.Value last_key_value;
        list_store.get_value(iter, Column.LAST_KEY, out last_key_value);
        string? last_key = last_key_value.get_string();
        if (current_address_key != last_key) {
            list_store.set(iter,
                Column.CONTACT_MARKUP_NAME, highlighted_result,
                Column.LAST_KEY, current_address_key, -1);
        }
        
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
        
        int cursor_position = entry.cursor_position;
        if (cursor_position < 0)
            return empty_addresses;
        
        string? original_text = entry.get_text();
        if (original_text == null)
            return empty_addresses;
        
        Gee.List<string> addresses = new Gee.ArrayList<string>();
        string delimiter = ",";
        string[] addresses_array = original_text.split(delimiter);
        foreach (string address in addresses_array)
            addresses.add(address);
        
        if (addresses.size < 1)
            return empty_addresses;
        
        int characters_seen_so_far = 0;
        current_address_index = addresses.size - 1;
        for (int i = 0; i < addresses.size; i++) {
            int token_chars = addresses[i].char_count() + delimiter.char_count();
            if ((characters_seen_so_far + token_chars) > cursor_position) {
                current_address_index = i;
                current_address_key = addresses[i]
                    .substring(0, cursor_position - characters_seen_so_far)
                    .strip().normalize().casefold();
                
                current_address_remainder = addresses[i]
                    .substring(cursor_position - characters_seen_so_far).strip();
                break;
            }
            characters_seen_so_far += token_chars;
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
        bool email_match = match_prefix_string(needle, contact.normalized_email, out email_result);
        
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
        if (haystack == null)
            return false;
        
        string escaped_haystack = Markup.escape_text(haystack);
        // Default result if there is no match or we encounter an error.
        highlighted_result = escaped_haystack;
        
        try {
            string escaped_needle = Regex.escape_string(Markup.escape_text(needle.normalize()));
            Regex regex = new Regex("\\b" + escaped_needle, RegexCompileFlags.CASELESS);
            if (regex.match(escaped_haystack)) {
                highlighted_result = regex.replace_eval(escaped_haystack, -1, 0, 0, eval_callback);
                return true;
            }
        } catch (RegexError err) {
            debug("Error matching regex: %s", err.message);
        }
        
        return false;
    }

    private bool eval_callback(MatchInfo match_info, StringBuilder result) {
        string? match = match_info.fetch(0);
        if (match != null) {
            // The target was escaped before the regex was run against it, so we don't have to
            // worry about markup injections here.
            result.append("<b>%s</b>".printf(match));
        }
        
        return false;
    }
    
    private int sort_func(Gtk.TreeModel model, Gtk.TreeIter aiter, Gtk.TreeIter biter) {
        // Order by importance, then by real name, then by email.
        GLib.Value avalue, bvalue;
        model.get_value(aiter, Column.CONTACT_OBJECT, out avalue);
        model.get_value(biter, Column.CONTACT_OBJECT, out bvalue);
        Geary.Contact? acontact = avalue.get_object() as Geary.Contact;
        Geary.Contact? bcontact = bvalue.get_object() as Geary.Contact;
        
        // Contacts can be null if the sort func is called between TreeModel.append and
        // TreeModel.set.
        if (acontact == bcontact)
            return 0;
        if (acontact == null && bcontact != null)
            return -1;
        if (acontact != null && bcontact == null)
            return 1;
        
        // First order by importance.
        if (acontact.highest_importance > bcontact.highest_importance)
            return -1;
        if (acontact.highest_importance < bcontact.highest_importance)
            return 1;
        
        // Then order by real name.
        string? anormalized_real_name = acontact.real_name == null ? null :
            acontact.real_name.normalize().casefold();
        string? bnormalized_real_name = bcontact.real_name == null ? null :
            bcontact.real_name.normalize().casefold();
        // strcmp correctly marks 'null' as first in lexigraphic order, so we don't need to
        // special-case it.
        int result = strcmp(anormalized_real_name, bnormalized_real_name);
        if (result != 0)
            return result;
        
        // Finally, order by email.
        return strcmp(acontact.normalized_email, bcontact.normalized_email);
    }
}

