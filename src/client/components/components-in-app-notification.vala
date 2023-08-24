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

    private uint duration;

    /**
     * Creates an in-app notification.
     *
     * @param message The message that should be displayed.
     * @param duration The length of time to show the notification,
     * in seconds.
     */
    public InAppNotification(string message,
                             uint duration = DEFAULT_DURATION) {
        this.transition_type = Gtk.RevealerTransitionType.CROSSFADE;
        this.message_label.label = message;
        this.duration = duration;
    }

    /**
     * Sets a button for the notification.
     */
    public void set_button(string label, string action_name) {
        this.action_button.visible = true;
        this.action_button.label = label;
        this.action_button.action_name = action_name;
    }

    public override void show() {
        if (this.duration > 0) {
            base.show();
            this.reveal_child = true;

            // Close after the given amount of time
            GLib.Timeout.add_seconds(
                this.duration, () => { close(); return false; }
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
    }

    // Make sure the notification gets destroyed after closing.
    [GtkCallback]
    private void on_child_revealed(Object src, ParamSpec p) {
        if (!this.child_revealed)
            destroy();
    }
}
