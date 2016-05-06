/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerToolbar : PillToolbar {
    
    public string label_text { get; set; }
    
    public ComposerToolbar(Gtk.ActionGroup toolbar_action_group, Gtk.Menu menu) {
        base(toolbar_action_group);
        
        Gee.List<Gtk.Button> insert = new Gee.ArrayList<Gtk.Button>();
        
        // Font formatting.
        insert.add(create_toggle_button(null, ComposerWidget.ACTION_BOLD));
        insert.add(create_toggle_button(null, ComposerWidget.ACTION_ITALIC));
        insert.add(create_toggle_button(null, ComposerWidget.ACTION_UNDERLINE));
        insert.add(create_toggle_button(null, ComposerWidget.ACTION_STRIKETHROUGH));
        add_start(create_pill_buttons(insert, false, true));
        
        // Indent level.
        insert.clear();
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_INDENT));
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_OUTDENT));
        add_start(create_pill_buttons(insert, false));
        
        // Link.
        insert.clear();
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_INSERT_LINK));
        add_start(create_pill_buttons(insert));
        
        // Remove formatting.
        insert.clear();
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_REMOVE_FORMAT));
        add_start(create_pill_buttons(insert));
        
        // Menu.
        insert.clear();
        insert.add(create_menu_button(null, menu, ComposerWidget.ACTION_MENU));
        add_end(create_pill_buttons(insert));
        
        Gtk.Label label = new Gtk.Label(null);
        label.get_style_context().add_class("dim-label");
        bind_property("label-text", label, "label", BindingFlags.SYNC_CREATE);
        add_end(label);
    }
}

