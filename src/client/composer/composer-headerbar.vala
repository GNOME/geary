/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerHeaderbar : PillHeaderbar {
    
    public ComposerWidget.ComposerState state { get; set; }
    public bool show_pending_attachments { get; set; default = false; }
    public bool send_enabled { get; set; default = false; }
    public bool show_detach_button { get; set; default = true; }
    
    private Gtk.Button recipients;
    private Gtk.Label recipients_label;
    
    public ComposerHeaderbar(Gtk.ActionGroup action_group) {
        base(action_group);
        
        show_close_button = false;
        
        // Toolbar setup.
        Gee.List<Gtk.Button> insert = new Gee.ArrayList<Gtk.Button>();
        
        // Window management.
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_CLOSE_DISCARD));
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_CLOSE_SAVE));
        Gtk.Button detach_button = create_toolbar_button(null, ComposerWidget.ACTION_DETACH);
        bind_property("show-detach-button", detach_button, "visible", BindingFlags.SYNC_CREATE);
        insert.add(detach_button);
        Gtk.Button send_button = create_toolbar_button(null, ComposerWidget.ACTION_SEND, true);
        send_button.get_style_context().add_class("suggested-action");
        insert.add(send_button);
        Gtk.Box window_buttons = create_pill_buttons(insert, false);
        
        insert.clear();
        
        Gtk.Box attach_buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Button attach_only = create_toolbar_button(null, ComposerWidget.ACTION_ADD_ATTACHMENT);
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_ADD_ATTACHMENT));
        insert.add(create_toolbar_button(null, ComposerWidget.ACTION_ADD_ORIGINAL_ATTACHMENTS));
        Gtk.Box attach_pending = create_pill_buttons(insert, false);
        attach_buttons.pack_start(attach_only);
        attach_buttons.pack_start(attach_pending);
        
        recipients = new Gtk.Button();
        recipients.set_relief(Gtk.ReliefStyle.NONE);
        recipients_label = new Gtk.Label(null);
        recipients_label.set_ellipsize(Pango.EllipsizeMode.END);
        recipients.add(recipients_label);
        recipients.clicked.connect(() => { state = ComposerWidget.ComposerState.INLINE; });
        
        bind_property("state", recipients, "visible", BindingFlags.SYNC_CREATE,
            (binding, source_value, ref target_value) => {
                target_value = (state == ComposerWidget.ComposerState.INLINE_COMPACT);
                return true;
            });
        bind_property("show-pending-attachments", attach_only, "visible",
            BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
        bind_property("show-pending-attachments", attach_pending, "visible",
            BindingFlags.SYNC_CREATE);
        bind_property("send-enabled", send_button, "sensitive", BindingFlags.SYNC_CREATE);
        
        add_start(attach_buttons);
        add_start(recipients);
        add_end(window_buttons);
    }
    
    public void set_recipients(string label, string tooltip) {
        recipients_label.label = label;
        recipients.tooltip_text = tooltip;
    }
}

