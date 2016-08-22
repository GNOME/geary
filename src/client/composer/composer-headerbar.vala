/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/composer-headerbar.ui")]
public class ComposerHeaderbar : Gtk.HeaderBar {

    public ComposerWidget.ComposerState state { get; set; }

    public bool show_pending_attachments { get; set; default = false; }

    [GtkChild]
    private Gtk.Box detach_start;
    [GtkChild]
    private Gtk.Box detach_end;
    [GtkChild]
    private Gtk.Button recipients_button;
    [GtkChild]
    private Gtk.Label recipients_label;
    [GtkChild]
    private Gtk.Button new_message_attach_button;
    [GtkChild]
    private Gtk.Box conversation_attach_buttons;
    [GtkChild]
    private Gtk.Button send_button;

    public ComposerHeaderbar() {
        recipients_button.clicked.connect(() => { state = ComposerWidget.ComposerState.INLINE; });

        send_button.image = new Gtk.Image.from_icon_name("mail-send-symbolic", Gtk.IconSize.MENU);

        bind_property("state", recipients_button, "visible", BindingFlags.SYNC_CREATE,
            (binding, source_value, ref target_value) => {
                target_value = (state == ComposerWidget.ComposerState.INLINE_COMPACT);
                return true;
            });
        bind_property("show-pending-attachments", new_message_attach_button, "visible",
            BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
        bind_property("show-pending-attachments", conversation_attach_buttons, "visible",
            BindingFlags.SYNC_CREATE);

        notify["decoration-layout"].connect(set_detach_button_side);
        realize.connect(set_detach_button_side);
        notify["state"].connect((s, p) => {
            if (state == ComposerWidget.ComposerState.DETACHED) {
                notify["decoration-layout"].disconnect(set_detach_button_side);
                detach_start.visible = detach_end.visible = false;
            }
        });
    }

    public void set_recipients(string label, string tooltip) {
        recipients_label.label = label;
        recipients_button.tooltip_text = tooltip;
    }

    private void set_detach_button_side() {
        bool at_end = GtkUtil.close_button_at_end();
        detach_start.visible = !at_end;
        detach_end.visible = at_end;
    }
}

