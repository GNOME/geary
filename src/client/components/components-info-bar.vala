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


    private Plugin.InfoBar? plugin = null;
    private string? plugin_action_group_name = null;
    private Gtk.Button? plugin_primary_button = null;


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
                              string action_group_name,
                              int priority) {
        this(plugin.status, plugin.description);
        this.plugin = plugin;
        this.plugin_action_group_name = action_group_name;
        this.show_close_button = plugin.show_close_button;

        plugin.notify["status"].connect(
            () => { this.status.label = plugin.status; }
        );
        plugin.notify["description"].connect(
            () => { this.description.label = plugin.description; }
        );
        plugin.notify["primary-button"].connect(
            () => { this.update_plugin_primary_button(); }
        );

        var secondaries = plugin.secondary_buttons.bidir_list_iterator();
        bool has_prev = secondaries.last();
        while (has_prev) {
            get_action_area().add(new_plugin_button(secondaries.get()));
            has_prev = secondaries.previous();
        }
        update_plugin_primary_button();

        set_data<int>(InfoBarStack.PRIORITY_QUEUE_KEY, priority);

        show_all();
    }

    /* {@inheritDoc} */
    public override void response(int response) {
        if (response == Gtk.ResponseType.CLOSE && this.plugin != null) {
            this.plugin.close_activated();
        }
    }

    /* {@inheritDoc} */
    public override void destroy() {
        this.plugin = null;
    }

    // GTK 3.24.16 fixed the binding for this, but that and the VAPI
    // change has yet to trickle down to common distros like F31
    public new Gtk.Box get_action_area() {
        return (Gtk.Box) base.get_action_area();
    }

    private void update_plugin_primary_button() {
        Gtk.Button? new_button = null;
        if (this.plugin != null && this.plugin.primary_button != null) {
            new_button = new_plugin_button(this.plugin.primary_button);
        }
        if (this.plugin_primary_button != null) {
            get_action_area().remove(plugin_primary_button);
        }
        if (new_button != null) {
            get_action_area().add(new_button);
        }
        this.plugin_primary_button = new_button;
    }

    private Gtk.Button new_plugin_button(Plugin.Actionable ui) {
        Gtk.Button? button = null;
        if (ui.icon_name == null) {
            button = new Gtk.Button.with_label(ui.label);
        } else {
            var icon = new Gtk.Image.from_icon_name(
                ui.icon_name, Gtk.IconSize.BUTTON
            );
            button = new Gtk.Button();
            button.add(icon);
            button.tooltip_text = ui.label;
        }
        button.set_action_name(
            this.plugin_action_group_name + "." + ui.action.name
        );
        if (ui.action_target != null) {
            button.set_action_target_value(ui.action_target);
        }
        button.show_all();
        return button;
    }

}
