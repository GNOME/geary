/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Enables plugins to add buttons to the user interface.
 */
public class Plugin.Button : Geary.BaseObject {


    /**
     * A short human-readable button label.
     *
     * This should ideally be less than 10 characters long.
     */
    public string label { get; private set; }

    /** The action to be invoked when the button is clicked. */
    public GLib.Action action { get; private set; }

    /** The parameter value for the action, if any. */
    public GLib.Variant? action_target { get; private set; }

    /** Constructs a new button with a text label. */
    public Button(string label,
                  GLib.Action action,
                  GLib.Variant? action_target = null) {
        this.label = label;
        this.action = action;
        this.action_target = action_target;
    }

}
