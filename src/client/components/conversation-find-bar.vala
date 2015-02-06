/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationFindBar : Gtk.Layout {
    private static const string entry_not_found_style =
"""
.geary-not-found {
    color: white;
    background-color: #FF6969;
    background-image: none;
}
.geary-not-found:selected {
    color: grey;
    background-color: white;
    background-image: none;
}
""";
    
    private Gtk.Builder builder;
    private Gtk.Box contents_box;
    private Gtk.Entry entry;
    private ConversationWebView web_view;
    private Gtk.Label result_label;
    private Gtk.CheckButton case_sensitive_check;
    private Gtk.Button next_button;
    private Gtk.Button prev_button;
    private bool wrapped;
    private uint matches;
    private bool searching = false;
    
    public signal void close();
    
    public ConversationFindBar(ConversationWebView web_view) {
        this.web_view = web_view;
        
        builder = GearyApplication.instance.create_builder("find_bar.glade");
        
        key_press_event.connect(on_key_press);
        button_press_event.connect(on_button_press);
        
        contents_box = (Gtk.Box) builder.get_object("box: contents");
        add(contents_box);
        
        entry = (Gtk.Entry) builder.get_object("entry: find");
        entry.buffer.inserted_text.connect(on_entry_buffer_inserted_text);
        entry.buffer.deleted_text.connect(on_entry_buffer_deleted_text);
        entry.activate.connect(on_entry_activate);
        
        GtkUtil.apply_style(entry, entry_not_found_style);
        
        result_label = (Gtk.Label) builder.get_object("label: result");
        update_result_label();
        
        prev_button = (Gtk.Button) builder.get_object("button: previous");
        prev_button.set_sensitive(false);
        prev_button.clicked.connect(on_previous_button_clicked);
        
        next_button = (Gtk.Button) builder.get_object("button: next");
        next_button.set_sensitive(false);
        next_button.clicked.connect(on_next_button_clicked);
        
        Gtk.Button close_button = (Gtk.Button) builder.get_object("button: close");
        close_button.clicked.connect(on_close_button_clicked);
        
        case_sensitive_check = (Gtk.CheckButton) builder.get_object("check: case_sensitive");
        case_sensitive_check.toggled.connect(on_case_sensitive_check_toggled);
    }
    
    public override void show() {
        // Make the width of the find bar completely obey its parent and the height fixed
        int minimal_height, natural_height;
        contents_box.get_preferred_height(out minimal_height, out natural_height);
        set_size_request(-1, minimal_height);
        
        base.show();
        
        fill_entry_with_web_view_selection();
        commence_search();
    }
    
    public override void hide() {
        base.hide();
        
        end_search();
        close();
    }
    
    public void focus_entry() {
        entry.grab_focus();
    }
    
    private void highlight_text_matches() {
        if (entry.buffer.text == "")
            return;
        
        searching = true;
        
        web_view.unmark_text_matches();
        matches = web_view.mark_text_matches(entry.text, case_sensitive_check.active, 0);
        web_view.set_highlight_text_matches(true);
        
        update_result_label();
        color_according_to_result();
    }
    
    public void commence_search() {
        wrapped = false;
        matches = 0;
        
        highlight_text_matches();
    }
    
    public void end_search() {
        if (searching) {
            web_view.unmark_text_matches();
            searching = false;
        }
        web_view.selection_changed.disconnect(on_web_view_selection_changed);
        switch_to_usual_selection_color();
    }
    
    private void on_entry_buffer_inserted_text(uint position, string text, uint n_chars) {
        highlight_text_matches();
        set_button_sensitivity();
    }
    
    private void color_according_to_result() {
        Gtk.StyleContext entry_style_context = entry.get_style_context();
        
        if (searching && matches == 0)
            entry_style_context.add_class("geary-not-found");
        else
            entry_style_context.remove_class("geary-not-found");
    }
    
    private void on_entry_buffer_deleted_text(uint position, uint n_chars) {
        if (entry.text.length == 0) {
            web_view.unmark_text_matches();
            searching = false;
        } else {
            highlight_text_matches();
        }
        
        update_result_label();
        color_according_to_result();
        set_button_sensitivity();
    }
    
    private bool on_key_press(Gdk.EventKey event) {
        switch (event.keyval) {
            case Gdk.Key.Escape:
                hide();
                return true;
                
            case Gdk.Key.Return:
                if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    find(false);
                    return true;
                }
                return false;
            }
        
        return false;
    }
    
    public void find(bool forward) {
        web_view.selection_changed.disconnect(on_web_view_selection_changed);
        
        bool first_result;
        first_result = web_view.search_text(entry.buffer.text, case_sensitive_check.active,
            forward, false);
        
        if (!first_result) {
            wrapped = web_view.search_text(entry.buffer.text, case_sensitive_check.active, 
                forward, true);
        } else {
            wrapped = false;
        }
        
        if (wrapped || first_result) {
            // An item has been found. Switch the selection color so it is easily discernible
            // from the surrounding unselected (but also highlighted) matches.
            switch_to_search_selection_color();
            
            // If the user selects something on their own, switch back to the original
            // selection color.
            web_view.selection_changed.connect(on_web_view_selection_changed);
        }
        
        update_result_label();
    }
    
    private void set_button_sensitivity() {
        bool sensitive = (matches != 0 && searching);
        
        prev_button.set_sensitive(sensitive);
        next_button.set_sensitive(sensitive);
    }
    
    private void update_result_label() {
        string content = "|  ";
        
        if (searching) {
            result_label.show();
        } else {
            result_label.hide();
        }
        
        if (matches > 0) {
            if (!wrapped)
                content += ngettext("%i match", "%i matches", matches).printf(matches);
            else
                content += ngettext("%i match (wrapped)", "%i matches (wrapped)", matches).printf(matches);
        } else {
            content += _("not found");
        }
        
        result_label.set_markup(content);
    }
    
    private void fill_entry_with_web_view_selection() {
        WebKit.DOM.Document document;
        document = web_view.get_dom_document();
        
        WebKit.DOM.DOMWindow window;
        window = document.get_default_view();
        
        WebKit.DOM.DOMSelection selection;
        selection = window.get_selection();
        
        if (selection.get_range_count() <= 0)
            return;
        
        try {
            WebKit.DOM.Range range = selection.get_range_at (0);
            
            if (range.get_text() != "")
                entry.text = range.get_text();
        } catch (Error e) {
            warning("Could not get selected text from web view: %s", e.message);
        }
    }
    
    private void on_web_view_selection_changed() {
        web_view.selection_changed.disconnect(on_web_view_selection_changed);
        switch_to_usual_selection_color();
    }
    
    private void switch_to_search_selection_color() {
        try {
            web_view.get_dom_document().get_body().get_class_list().add("search_coloring");
        } catch (Error error) {
            warning("Error setting body class for search selection coloring: %s", error.message);
        }
    }
    
    private void switch_to_usual_selection_color() {
        try {
            web_view.get_dom_document().get_body().get_class_list().remove("search_coloring");
        } catch (Error error) {
            warning("Error setting body class for search selection coloring: %s", error.message);
        }
    }
    
    public override void size_allocate(Gtk.Allocation allocation) {
        // Fit the box to the actual width of the bar
        contents_box.set_size_request(allocation.width, -1);
        
        base.size_allocate(allocation);
    }
    
    private void on_entry_activate() {
        find(true);
    }
    
    private bool on_button_press(Gdk.EventButton event) {
        focus_entry();
        return true;
    }
    
    private void on_next_button_clicked() {
        find(true);
    }
    
    private void on_previous_button_clicked() {
        find(false);
    }
    
    private void on_close_button_clicked() {
        hide();
    }
    
    private void on_case_sensitive_check_toggled() {
        commence_search();
        set_button_sensitivity();
    }
}
