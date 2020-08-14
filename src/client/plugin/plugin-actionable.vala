/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Enables plugins to add user interface elements such as buttons.
 *
 * Depending on how it is used, this interface may be used to specify
 * buttons, menu items, and so on. The associated action must be
 * registered via {@link Application.register_action} or similar calls
 * for it to be enabled.
 */
public class Plugin.Actionable : Geary.BaseObject {


    /**
     * A short human-readable label for the actionable.
     *
     * This should ideally be less than 10 characters long. It will be
     * used as the label for the button, menu item, etc, depending on
     * how it was registered.
     */
    public string label { get; private set; }

    /**
     * The name of an icon from the current icon theme to display.
     *
     * How and if the image displayed depends on the context and
     * implementation. When used for a button, this may be displayed
     * instead of {@link label}, for menu items it may not be
     * displayed at all.
     */
    public string? icon_name { get; private set; default = null; }

    /** The action to be invoked when the actionable is activated. */
    public GLib.Action action { get; private set; }

    /** The parameter value for the action, if any. */
    public GLib.Variant? action_target { get; private set; }

    /** Constructs a new actionable with a text label. */
    public Actionable(string label,
                      GLib.Action action,
                      GLib.Variant? action_target = null) {
        this.label = label;
        this.action = action;
        this.action_target = action_target;
    }

    /** Constructs a new actionable with a text label and icon name. */
    public Actionable.with_icon(string label,
                                string icon_name,
                                GLib.Action action,
                                GLib.Variant? action_target = null) {
        this.label = label;
        this.icon_name = icon_name;
        this.action = action;
        this.action_target = action_target;
    }

}
