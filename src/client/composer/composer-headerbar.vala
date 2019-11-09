/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/composer-headerbar.ui")]
public class Composer.Headerbar : Gtk.HeaderBar {

    public Application.Configuration config { get; set; }

    public Widget.ComposerState state { get; set; }

    public bool show_pending_attachments { get; set; default = false; }

    [GtkChild]
    internal Gtk.Button save_and_close_button; // { get; private set; }

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

    /** Fired when the user wants to expand a compact composer. */
    public signal void expand_composer();

    public Headerbar(Application.Configuration config, bool is_compact) {
        this.config = config;

        this.recipients_button.set_visible(is_compact);
        this.recipients_button.clicked.connect(() => {
                this.recipients_button.hide();
                expand_composer();
            });

        bind_property("show-pending-attachments", new_message_attach_button, "visible",
            BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
        bind_property("show-pending-attachments", conversation_attach_buttons, "visible",
            BindingFlags.SYNC_CREATE);

        set_detach_button_side();
        Gtk.Settings.get_default().notify["gtk-decoration-layout"].connect(
            () => { set_detach_button_side(); }
        );
    }

    public void set_recipients(string label, string tooltip) {
        recipients_label.label = label;
        recipients_button.tooltip_text = tooltip;
    }

    public void detached() {
        notify["decoration-layout"].disconnect(set_detach_button_side);
        this.recipients_button.hide();
        this.detach_start.visible = this.detach_end.visible = false;
    }

    private void set_detach_button_side() {
        if (config.desktop_environment == UNITY) {
            detach_start.visible = false;
            detach_end.visible = true;
        } else {
            bool at_end = Util.Gtk.close_button_at_end();
            detach_start.visible = !at_end;
            detach_end.visible = at_end;
        }
    }
}
