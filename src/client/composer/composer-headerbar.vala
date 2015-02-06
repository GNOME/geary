/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ComposerHeaderbar : PillHeaderbar {
    
    public ComposerWidget.ComposerState state { get; set; }
    public bool show_pending_attachments { get; set; default = false; }
    public bool send_enabled { get; set; default = false; }
    
    private Gtk.Button recipients;
    private Gtk.Label recipients_label;
    private Gtk.Box win_buttons_start;
    private Gtk.Box win_buttons_end;
    
    public ComposerHeaderbar(Gtk.ActionGroup action_group) {
        base(action_group);
        
        show_close_button = false;
        
        Gtk.Button send_button = create_toolbar_button(null, ComposerWidget.ACTION_SEND, true);
        send_button.get_style_context().add_class("suggested-action");
        
        bool rtl = (get_direction() == Gtk.TextDirection.RTL);
        
        win_buttons_start = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Button detach_button = create_toolbar_button(null, ComposerWidget.ACTION_DETACH);
        Gtk.Button close_button = create_toolbar_button(null, ComposerWidget.ACTION_CLOSE);
        detach_button.set_relief(Gtk.ReliefStyle.NONE);
        close_button.set_relief(Gtk.ReliefStyle.NONE);
        if (rtl)
            detach_button.set_margin_left(6);
        else
            detach_button.set_margin_right(6);
        win_buttons_start.pack_start(close_button);
        win_buttons_start.pack_start(detach_button);
        win_buttons_start.pack_start(new Gtk.Separator(Gtk.Orientation.VERTICAL));
        
        win_buttons_end = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        detach_button = create_toolbar_button(null, ComposerWidget.ACTION_DETACH);
        close_button = create_toolbar_button(null, ComposerWidget.ACTION_CLOSE);
        detach_button.set_relief(Gtk.ReliefStyle.NONE);
        close_button.set_relief(Gtk.ReliefStyle.NONE);
        if (rtl)
            detach_button.set_margin_right(6);
        else
            detach_button.set_margin_left(6);
        win_buttons_end.pack_end(close_button);
        win_buttons_end.pack_end(detach_button);
        win_buttons_end.pack_end(new Gtk.Separator(Gtk.Orientation.VERTICAL));
        
        Gtk.Box attach_buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Button attach_only = create_toolbar_button(null, ComposerWidget.ACTION_ADD_ATTACHMENT);
        Gee.List<Gtk.Button> insert = new Gee.ArrayList<Gtk.Button>();
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
        
        notify["state"].connect((s, p) => {
            if (state == ComposerWidget.ComposerState.DETACHED) {
                get_style_context().changed.disconnect(set_win_buttons_side);
                win_buttons_start.visible = win_buttons_end.visible = false;
            }
        });
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
        
        add_start(win_buttons_start);
        add_start(attach_buttons);
        add_start(recipients);
#if !GTK_3_12
        add_end(send_button);
#endif
        add_end(win_buttons_end);
#if GTK_3_12
        add_end(send_button);
#endif
        get_style_context().changed.connect(set_win_buttons_side);
        realize.connect(set_win_buttons_side);
    }
    
    public void set_recipients(string label, string tooltip) {
        recipients_label.label = label;
        recipients.tooltip_text = tooltip;
    }
    
    private void set_win_buttons_side() {
        string layout;
        bool at_end = false;
        get_toplevel().style_get("decoration-button-layout", out layout);
        // Based on logic of close_button_at_end in gtkheaderbar.c: Close button appears
        // at end iff "close" follows a colon in the layout string.
        if (layout != null) {
            int colon_ind = layout.index_of(":");
            at_end = (colon_ind >= 0 && layout.index_of("close", colon_ind) >= 0);
        }
        win_buttons_start.visible = !at_end;
        win_buttons_end.visible = at_end;
    }
}

