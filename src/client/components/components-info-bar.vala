/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A standard info bar widget with status message and description.
 */
public class Components.InfoBar : Gtk.InfoBar {


    /**
     * A short, human-readable status message.
     *
     * This should ideally be less than 20 characters long.
     */
    public Gtk.Label status { get; private set; }

    /**
     * An optional, longer human-readable explanation of the status.
     *
     * This provides additional information and context for {@link
     * status}.
     */
    public Gtk.Label? description { get; private set; default = null; }


    /**
     * Constructs a new info bar.
     *
     * @param status a short, human-readable status message, ideally
     * less than 20 characters long
     * @param description an optional, longer human-readable
     * explanation of {@link status}.
     */
    public InfoBar(string status, string? description = null) {
        this.status = new Gtk.Label(status);
        this.status.halign = START;

        var attrs = new Pango.AttrList();
        attrs.change(Pango.attr_weight_new(BOLD));
        this.status.attributes = attrs;

        if (!Geary.String.is_empty_or_whitespace(description)) {
            // There is both a status and a description, so they
            // should be vertical-aligned next to each other in the
            // centre
            this.status.valign = END;

            this.description = new Gtk.Label(description);
            this.description.halign = START;
            this.description.valign = START;

            // Set the description to be ellipsised and set and the
            // tool-tip to be the same, in case it is too long for the
            // info bar's width
            this.description.ellipsize = END;
            this.description.tooltip_text = description;
        }

        var container = new Gtk.Grid();
        container.orientation = VERTICAL;
        container.valign = CENTER;
        container.add(this.status);
        if (this.description != null) {
            container.add(this.description);
        }
        get_content_area().add(container);

        show_all();
    }

    public InfoBar.for_plugin(Plugin.InfoBar plugin,
                              string action_group_name) {
        this(plugin.status, plugin.description);
        this.show_close_button = plugin.show_close_button;

        var secondaries = plugin.secondary_buttons.bidir_list_iterator();
        bool has_prev = secondaries.last();
        while (has_prev) {
            add_plugin_button(secondaries.get(), action_group_name);
            has_prev = secondaries.previous();
        }
        if (plugin.primary_button != null) {
            add_plugin_button(plugin.primary_button, action_group_name);
        }

        show_all();
    }

    // GTK 3.24.16 fixed the binding for this, but that and the VAPI
    // change has yet to trickle down to common distros like F31
    public new Gtk.Box get_action_area() {
        return (Gtk.Box) base.get_action_area();
    }

    private void add_plugin_button(Plugin.Button plugin, string action_group_name) {
        var gtk = new Gtk.Button.with_label(plugin.label);
        gtk.set_action_name(action_group_name + "." + plugin.action.name);
        if (plugin.action_target != null) {
            gtk.set_action_target_value(plugin.action_target);
        }
        get_action_area().add(gtk);
    }

}
