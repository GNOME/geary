/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/composer-headerbar.ui")]
public class Composer.Headerbar : Hdy.HeaderBar {


    public bool show_save_and_close {
        get { return this.save_and_close_button.visible; }
        set { this.save_and_close_button.visible = value; }
    }

    public bool show_send {
        get { return this.send_button.visible; }
        set { this.send_button.visible = value; }
    }

    private Application.Configuration config;

    private bool is_attached = true;

    [GtkChild] private unowned Gtk.Box detach_start;
    [GtkChild] private unowned Gtk.Box detach_end;
    [GtkChild] private unowned Gtk.Button recipients_button;
    [GtkChild] private unowned Gtk.Label recipients_label;
    [GtkChild] private unowned Gtk.Button save_and_close_button;

    [GtkChild] private unowned Gtk.Button send_button;

    /** Fired when the user wants to expand a compact composer. */
    public signal void expand_composer();


    public Headerbar(Application.Configuration config) {
        this.config = config;
        Gtk.Settings.get_default().notify["gtk-decoration-layout"].connect(
            on_gtk_decoration_layout_changed
        );
    }

    public override void destroy() {
        Gtk.Settings.get_default().notify["gtk-decoration-layout"].disconnect(
            on_gtk_decoration_layout_changed
        );
        base.destroy();
    }

    public void set_recipients(string label, string tooltip) {
        recipients_label.label = label;
        recipients_button.tooltip_text = tooltip;
    }

    internal void set_mode(Widget.PresentationMode mode) {
        switch (mode) {
        case Widget.PresentationMode.DETACHED:
            this.recipients_button.visible = false;
            this.set_attached(false);
            break;

        case Widget.PresentationMode.PANED:
        case Widget.PresentationMode.INLINE:
            this.recipients_button.visible = false;
            this.set_attached(true);
            break;

        case Widget.PresentationMode.INLINE_COMPACT:
            this.recipients_button.visible = true;
            this.set_attached(true);
            break;

        case Widget.PresentationMode.CLOSED:
        case Widget.PresentationMode.NONE:
            // no-op
            break;
        }

        this.show_close_button = (mode == Widget.PresentationMode.PANED
                                  && this.config.desktop_environment != UNITY);
    }

    private void set_attached(bool is_attached) {
        this.is_attached = is_attached;
        if (is_attached) {
            set_detach_button_side();
        } else {
            this.detach_start.visible = this.detach_end.visible = false;
        }
    }

    private void set_detach_button_side() {
        if (this.is_attached) {
            if (this.config.desktop_environment == UNITY) {
                this.detach_start.visible = false;
                this.detach_end.visible = true;
            } else {
                bool at_end = Util.Gtk.close_button_at_end();
                this.detach_start.visible = !at_end;
                this.detach_end.visible = at_end;
            }
        }
    }

    [GtkCallback]
    private void on_recipients_button_clicked() {
        expand_composer();
    }

    private void on_gtk_decoration_layout_changed() {
        set_detach_button_side();
    }

}
