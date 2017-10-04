/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic interface for widgets that have a single ComposerWidget-child.
 */
public interface ComposerContainer {

    // The ComposerWidget-child.
    internal abstract ComposerWidget composer { get; set; }

    // Workaround to retrieve all Gtk.Actions with conflicting accelerators
    protected const string[] conflicting_actions = {
        GearyController.ACTION_MARK_AS_UNREAD,
        GearyController.ACTION_FORWARD_MESSAGE
    };

    // We use old_accelerators to keep track of the accelerators we temporarily disabled.
    protected abstract Gee.MultiMap<string, string>? old_accelerators { get; set; }

    public abstract void close_container();

    /**
     * Hides the widget (and possibly its parent). Usecase is when you don't want to close just yet
     * but the composer should not be visible any longer (e.g. when you're still saving a draft).
     */
    public abstract void vanish();

    /**
     * Removes the composer from this ComposerContainer (e.g. when detaching)
     */
    public abstract void remove_composer();

    // The toplevel window for the container. Note that it needs to be a GtkApplicationWindow.
    protected abstract Gtk.ApplicationWindow top_window { get; }

    protected virtual bool on_focus_in() {
        if (this.old_accelerators == null) {
            this.old_accelerators = new Gee.HashMultiMap<string, string>();
            add_accelerators();
        }
        return false;
    }

    protected virtual bool on_focus_out() {
        if (this.old_accelerators != null) {
            remove_accelerators();
            this.old_accelerators = null;
        }
        return false;
    }

    /**
     * Adds the accelerators for the child composer, and temporarily removes conflicting
     * accelerators from existing actions.
     */
    protected virtual void add_accelerators() {
        GearyApplication app = GearyApplication.instance;

        // Check for actions with conflicting accelerators
        foreach (string action in ComposerWidget.action_accelerators.get_keys()) {
            foreach (string accelerator in ComposerWidget.action_accelerators[action]) {
                string[] actions = app.get_actions_for_accel(accelerator);

                foreach (string conflicting_action in actions) {
                    remove_conflicting_accelerator(conflicting_action, accelerator);
                    this.old_accelerators[conflicting_action] = accelerator;
                }
            }
        }

        // Very stupid workaround while we still use Gtk.Actions in the GearyController
        foreach (string conflicting_action in conflicting_actions)
            app.actions.get_action(conflicting_action).disconnect_accelerator();

        // Now add our actions to the window and their accelerators
        foreach (string action in ComposerWidget.action_accelerators.get_keys()) {
            this.top_window.add_action(composer.get_action(action));
            app.set_accels_for_action("win." + action,
                                      ComposerWidget.action_accelerators[action].to_array());
        }
    }

    /**
     * Removes the accelerators for the child composer, and restores previously removed accelerators.
     */
    protected virtual void remove_accelerators() {
        foreach (string action in ComposerWidget.action_accelerators.get_keys())
            GearyApplication.instance.set_accels_for_action("win." + action, {});

        // Very stupid workaround while we still use Gtk.Actions in the GearyController
        foreach (string conflicting_action in conflicting_actions)
            GearyApplication.instance.actions.get_action(conflicting_action).connect_accelerator();

        foreach (string action in old_accelerators.get_keys())
            foreach (string accelerator in this.old_accelerators[action])
                restore_conflicting_accelerator(action, accelerator);
    }

    // Helper method. Removes the given conflicting accelerator from the action's accelerators.
    private void remove_conflicting_accelerator(string action, string accelerator) {
        GearyApplication app = GearyApplication.instance;
        string[] accelerators = app.get_accels_for_action(action);
        if (accelerators.length == 0)
            return;

        string[] without_accel = new string[accelerators.length - 1];
        foreach (string a in accelerators)
            if (a != accelerator)
                without_accel += a;

        app.set_accels_for_action(action, without_accel);
    }

    // Helper method. Adds the given accelerator back to the action's accelerators.
    private void restore_conflicting_accelerator(string action, string accelerator) {
        GearyApplication app = GearyApplication.instance;
        string[] accelerators = app.get_accels_for_action(action);
        accelerators += accelerator;
        app.set_accels_for_action(action, accelerators);
    }
}
