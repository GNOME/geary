/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents an in-app notification.
 *
 * Following the GNOME HIG, it should only contain a label and maybe a button.
 */
[GtkTemplate (ui = "/org/gnome/Geary/in-app-notification.ui")]
public class InAppNotification : Gtk.Revealer {

    /** Length of the default timeout to close the notification. */
    public const uint DEFAULT_KEEPALIVE = 5;

    [GtkChild]
    private Gtk.Label message_label;
    [GtkChild]
    private Gtk.Button action_button;

    /**
     * Creates an in-app notification.
     *
     * @param message The message that should be displayed.
     * @param keepalive The amount of seconds that the notification should stay visible.
     */
    public InAppNotification(string message, uint keepalive = DEFAULT_KEEPALIVE) {
        this.transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
        this.message_label.label = message;

        // Close after the given amount of time.
        Timeout.add_seconds(keepalive, () => { close(); return false; });
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
        base.show();
        this.reveal_child = true;
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
