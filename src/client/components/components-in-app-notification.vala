/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents an in-app notification.
 *
 * Following the GNOME HIG, it should only contain a label and maybe a button.
 * Looks like libadwaita toast, remove this when porting toward GTK4
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-in-app-notification.ui")]
public class Components.InAppNotification : Gtk.Revealer {

    /** Default length of time to show the notification. */
    public const uint DEFAULT_DURATION = 5;

    [GtkChild] private unowned Gtk.Label message_label;

    [GtkChild] private unowned Gtk.Button action_button;

    private uint? timeout_id = null;

    /**
     *
     * Show a new notification
     * @param message The message that should be displayed.
     * @param duration The length of time to show the notification,
     * in seconds.
     */
    public new void add_toast(string message,
                              uint duration = DEFAULT_DURATION,
                              string? label=null,
                              string? action_name=null,
                              string? action_target=null) {
        if (duration > 0) {
            if (this.timeout_id != null) {
                Source.remove(this.timeout_id);
                this.timeout_id = null;
            }
            this.message_label.label = message;
            this.action_button.label = label;
            this.action_button.action_name = action_name;

            if (action_target != null)
                this.action_button.action_target = new GLib.Variant("s", action_target);
            else
                this.action_button.action_target = null;

            this.action_button.visible = action_name != null;

            show();
            this.reveal_child = true;
            // Close after the given amount of time
            this.timeout_id = GLib.Timeout.add_seconds(
                duration, () => { close(); return false; }
            );
        }
    }

    /**
     * Closes the in-app notification.
     */
    [GtkCallback]
    public void close() {
        // Allows for the disappearing transition
        this.reveal_child = false;
        this.timeout_id = null;
    }

    // Make sure the notification gets hidden after closing.
    [GtkCallback]
    private void on_child_revealed(Object src, ParamSpec p) {
        if (!this.child_revealed)
            hide();
     }
}
