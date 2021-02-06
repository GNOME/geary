/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A standard info bar widget with status message and description.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-info-bar.ui")]
public class Components.InfoBar : Gtk.Box {
    public signal void response(int response_id);
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

    public bool show_close_button { get; set; default = false;}
    public bool revealed { get; set; }
    private Gtk.MessageType _message_type = Gtk.MessageType.OTHER;
    public Gtk.MessageType message_type {
        get {
            return _message_type;
        }
        set {
            _set_message_type(value);
        }
    }

    private Plugin.InfoBar? plugin = null;
    private string? plugin_action_group_name = null;
    private Gtk.Button? plugin_primary_button = null;

    [GtkChild] private unowned Gtk.Revealer revealer;

    [GtkChild] private unowned Gtk.Box action_area;

    [GtkChild] private unowned Gtk.Box content_area;

    [GtkChild] private unowned Gtk.Button close_button;

    static construct {
        set_css_name("infobar");
    }

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
        this.status.xalign = 0;

        _set_message_type(Gtk.MessageType.INFO);

        this.bind_property("revealed",
                           this.revealer,
                           "reveal-child",
                           BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        this.bind_property("show-close-button",
                           this.close_button,
                           "visible",
                           BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

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
            this.description.xalign = 0;
            this.description.wrap = true;
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

        _message_type = Gtk.MessageType.OTHER;
        _set_message_type(Gtk.MessageType.INFO);

        this.bind_property("revealed",
                           this.revealer,
                           "reveal-child",
                           BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        this.bind_property("show-close-button",
                           this.close_button,
                           "visible",
                           BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

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

    [GtkCallback]
    public void on_close_button_clicked() {
        if (this.plugin != null) {
            this.plugin.close_activated();
        }
        response(Gtk.ResponseType.CLOSE);
    }

    /* {@inheritDoc} */
    public override void destroy() {
        this.plugin = null;
        base.destroy();
    }

    public Gtk.Box get_action_area() {
        return this.action_area;
    }

    public Gtk.Box get_content_area() {
        return this.content_area;
    }

    public Gtk.Button add_button(string button_text, int response_id) {
        var button = new Gtk.Button.with_mnemonic(button_text);
        button.clicked.connect(() => {
            response(response_id);
        });
        get_action_area().add(button);
        button.visible = true;
        return button;
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

    private void _set_message_type(Gtk.MessageType message_type) {
        if (this._message_type != message_type) {
            Gtk.StyleContext context = this.get_style_context();
            const string[] type_class = {
                Gtk.STYLE_CLASS_INFO,
                Gtk.STYLE_CLASS_WARNING,
                Gtk.STYLE_CLASS_QUESTION,
                Gtk.STYLE_CLASS_ERROR,
                null
            };

            if (type_class[this._message_type] != null)
                context.remove_class(type_class[this._message_type]);

            this._message_type = message_type;

            var atk_obj = this.get_accessible();
            if (atk_obj is Atk.Object) {
                string name = null;

                atk_obj.set_role(Atk.Role.INFO_BAR);

                switch (message_type) {
                    case Gtk.MessageType.INFO:
                        name = _("Information");
                        break;

                    case Gtk.MessageType.QUESTION:
                        name = _("Question");
                        break;

                    case Gtk.MessageType.WARNING:
                        name = _("Warning");
                        break;

                    case Gtk.MessageType.ERROR:
                        name = _("Error");
                        break;

                    case Gtk.MessageType.OTHER:
                        break;

                    default:
                        warning("Unknown GtkMessageType %u", message_type);
                        break;
                }

                if (name != null)
                    atk_obj.set_name(name);
            }

            if (type_class[this._message_type] != null)
                context.add_class(type_class[this._message_type]);
        }
    }
}
