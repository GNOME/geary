/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Components.PreferencesWindow : Hdy.PreferencesWindow {


    private const string ACTION_CLOSE = "preferences-close";

    private const ActionEntry[] WINDOW_ACTIONS = {
        { Action.Window.CLOSE, on_close },
        { ACTION_CLOSE, on_close },
    };

    private class PluginRow : Hdy.ActionRow {

        private Peas.PluginInfo plugin;
        private Application.PluginManager plugins;
        private Gtk.Switch sw = new Gtk.Switch();


        public PluginRow(Peas.PluginInfo plugin,
                         Application.PluginManager plugins) {
            this.plugin = plugin;
            this.plugins = plugins;

            this.sw.active = plugin.is_loaded();
            this.sw.notify["active"].connect_after(() => update_plugin());
            this.sw.valign = CENTER;

            this.title = plugin.get_name();
            this.subtitle = plugin.get_description();
            this.activatable_widget = this.sw;
            this.add(this.sw);

            plugins.plugin_activated.connect((info) => {
                    if (this.plugin == info) {
                        this.sw.active = true;
                    }
                });
            plugins.plugin_deactivated.connect((info) => {
                    if (this.plugin == info) {
                        this.sw.active = false;
                    }
                });
            plugins.plugin_error.connect((info) => {
                    if (this.plugin == info) {
                        this.sw.active = false;
                        this.sw.sensitive = false;
                    }
                });
        }

        private void update_plugin() {
            if (this.sw.active && !this.plugin.is_loaded()) {
                bool loaded = false;
                try {
                    loaded = this.plugins.load_optional(this.plugin);
                } catch (GLib.Error err) {
                    warning(
                        "Plugin %s not able to be loaded: %s",
                        plugin.get_name(), err.message
                    );
                }
                if (!loaded) {
                    this.sw.active = false;
                }
            } else if (!sw.active && this.plugin.is_loaded()) {
                bool unloaded = false;
                try {
                    unloaded = this.plugins.unload_optional(this.plugin);
                } catch (GLib.Error err) {
                    warning(
                        "Plugin %s not able to be loaded: %s",
                        plugin.get_name(), err.message
                    );
                }
                if (!unloaded) {
                    this.sw.active = true;
                }
            }
        }

    }


    public static void add_accelerators(Application.Client app) {
        app.add_window_accelerators(ACTION_CLOSE, { "Escape" } );
    }


    /** Returns the window's associated client application instance. */
    public new Application.Client? application {
        get { return (Application.Client) base.get_application(); }
        set { base.set_application(value); }
    }

    private Application.PluginManager plugins;


    public PreferencesWindow(Application.MainWindow parent,
                             Application.PluginManager plugins) {
        Object(
            application: parent.application,
            default_width: 800,
            default_height: 600,
            transient_for: parent
        );
        this.plugins = plugins;

        add_general_pane();
        add_plugin_pane();
    }

    private void add_general_pane() {
        var autoselect = new Gtk.Switch();
        autoselect.valign = CENTER;

        var autoselect_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        autoselect_row.title = _("_Automatically select next message");
        autoselect_row.use_underline = true;
        autoselect_row.activatable_widget = autoselect;
        autoselect_row.add(autoselect);

        var display_preview = new Gtk.Switch();
        display_preview.valign = CENTER;

        var display_preview_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        display_preview_row.title = _("_Display conversation preview");
        display_preview_row.use_underline = true;
        display_preview_row.activatable_widget = display_preview;
        display_preview_row.add(display_preview);

        var single_key_shortucts = new Gtk.Switch();
        single_key_shortucts.valign = CENTER;

        var single_key_shortucts_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        single_key_shortucts_row.title = _("Use _single key email shortcuts");
        single_key_shortucts_row.tooltip_text = _(
            "Enable keyboard shortcuts for email actions that do not require pressing <Ctrl>"
        );
        single_key_shortucts_row.use_underline = true;
        single_key_shortucts_row.activatable_widget = single_key_shortucts;
        single_key_shortucts_row.add(single_key_shortucts);

        var startup_notifications = new Gtk.Switch();
        startup_notifications.valign = CENTER;

        var startup_notifications_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        startup_notifications_row.title = _("_Watch for new mail when closed");
        startup_notifications_row.use_underline = true;
        /// Translators: Preferences tooltip
        startup_notifications_row.tooltip_text = _(
            "Geary will keep running after all windows are closed"
        );
        startup_notifications_row.activatable_widget = startup_notifications;
        startup_notifications_row.add(startup_notifications);

        var trust_images = new Gtk.Switch();
        trust_images.valign = CENTER;

        var trust_images_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        trust_images_row.title = _("_Always load images");
        trust_images_row.subtitle = _("Showing remote images allows the sender to track you");
        trust_images_row.use_underline = true;
        trust_images_row.activatable_widget = trust_images;
        trust_images_row.add(trust_images);

        var unset_html_colors = new Gtk.Switch();
        unset_html_colors.valign = CENTER;

        var unset_html_colors_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        unset_html_colors_row.title = _("_Override the original colors in HTML emails");
        unset_html_colors_row.subtitle = _("Overrides the original colors in HTML messages to integrate better with the app theme. Requires restart.");
        unset_html_colors_row.use_underline = true;
        unset_html_colors_row.activatable_widget = unset_html_colors;
        unset_html_colors_row.add(unset_html_colors);

        var group = new Hdy.PreferencesGroup();
        /// Translators: Preferences group title
        //group.title = _("General");
        /// Translators: Preferences group description
        //group.description = _("General application preferences");
        group.add(autoselect_row);
        group.add(display_preview_row);
        group.add(single_key_shortucts_row);
        group.add(startup_notifications_row);
        group.add(trust_images_row);
        group.add(unset_html_colors_row);

        var page = new Hdy.PreferencesPage();
        /// Translators: Preferences page title
        page.title = _("Preferences");
        page.icon_name = "preferences-other-symbolic";
        page.add(group);
        page.show_all();

        add(page);

        GLib.SimpleActionGroup window_actions = new GLib.SimpleActionGroup();
        window_actions.add_action_entries(WINDOW_ACTIONS, this);
        insert_action_group(Action.Window.GROUP_NAME, window_actions);

        Application.Client? application = this.application;
        if (application != null) {
            Application.Configuration config = application.config;
            config.bind(
                Application.Configuration.AUTOSELECT_KEY,
                autoselect,
                "state"
            );
            config.bind(
                Application.Configuration.DISPLAY_PREVIEW_KEY,
                display_preview,
                "state"
            );
            config.bind(
                Application.Configuration.SINGLE_KEY_SHORTCUTS,
                single_key_shortucts,
                "state"
            );
            config.bind(
                Application.Configuration.RUN_IN_BACKGROUND_KEY,
                startup_notifications,
                "state"
            );
            config.bind_with_mapping(
                Application.Configuration.IMAGES_TRUSTED_DOMAINS,
                trust_images,
                "state",
                (GLib.SettingsBindGetMappingShared) settings_trust_images_getter,
                (GLib.SettingsBindSetMappingShared) settings_trust_images_setter
            );
            config.bind(
                Application.Configuration.UNSET_HTML_COLORS,
                unset_html_colors,
                "state"
            );
        }
    }

    private void add_plugin_pane() {
        var group = new Hdy.PreferencesGroup();
        /// Translators: Preferences group title
        //group.title = _("Plugins");
        /// Translators: Preferences group description
        //group.description = _("Optional features for Geary");

        Application.Client? application = this.application;
        if (application != null) {
            foreach (Peas.PluginInfo plugin in
                     this.plugins.get_optional_plugins()) {
                group.add(new PluginRow(plugin, this.plugins));
            }
        }

        var page = new Hdy.PreferencesPage();
        /// Translators: Preferences page title
        page.title = _("Plugins");
        page.icon_name = "application-x-addon-symbolic";
        page.add(group);
        page.show_all();

        add(page);
    }

    private void on_close() {
        close();
    }

    private static bool settings_trust_images_getter(GLib.Value value, GLib.Variant variant, void* user_data) {
        var domains = variant.get_strv();
        value.set_boolean(domains.length > 0 && domains[0] == "*");
        return true;
    }

    private static GLib.Variant settings_trust_images_setter(GLib.Value value, GLib.VariantType expected_type, void* user_data) {
        var trusted = value.get_boolean();
        string[] values = {};
        if (trusted)
            values += "*";
        return new GLib.Variant.strv(values);
    }
}
