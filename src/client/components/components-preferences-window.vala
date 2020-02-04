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


    public static void add_accelerators(Application.Client app) {
        app.add_window_accelerators(ACTION_CLOSE, { "Escape" } );
    }


    /** Returns the window's associated client application instance. */
    public new Application.Client application {
        get { return (Application.Client) base.get_application(); }
        set { base.set_application(value); }
    }


    public PreferencesWindow(Application.MainWindow parent) {
        Object(
            application: parent.application,
            transient_for: parent
        );

        var autoselect = new Gtk.Switch();
        autoselect.valign = CENTER;

        var autoselect_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        autoselect_row.title = _("_Automatically select next message");
        autoselect_row.use_underline = true;
        autoselect_row.activatable_widget = autoselect;
        autoselect_row.add_action(autoselect);

        var display_preview = new Gtk.Switch();
        display_preview.valign = CENTER;

        var display_preview_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        display_preview_row.title = _("_Display conversation preview");
        display_preview_row.use_underline = true;
        display_preview_row.activatable_widget = display_preview;
        display_preview_row.add_action(display_preview);

        var three_pane_view = new Gtk.Switch();
        three_pane_view.valign = CENTER;

        var three_pane_view_row = new Hdy.ActionRow();
        /// Translators: Preferences label
        three_pane_view_row.title = _("Use _three pane view");
        three_pane_view_row.use_underline = true;
        three_pane_view_row.activatable_widget = three_pane_view;
        three_pane_view_row.add_action(three_pane_view);

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
        single_key_shortucts_row.add_action(single_key_shortucts);

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
        startup_notifications_row.add_action(startup_notifications);

        var group = new Hdy.PreferencesGroup();
        /// Translators: Preferences group title
        //group.title = _("General");
        /// Translators: Preferences group description
        //group.description = _("General application preferences");
        group.add(autoselect_row);
        group.add(display_preview_row);
        group.add(three_pane_view_row);
        group.add(single_key_shortucts_row);
        group.add(startup_notifications_row);

        var page = new Hdy.PreferencesPage();
        page.propagate_natural_height = true;
        page.propagate_natural_width = true;
        page.add(group);
        page.show_all();

        add(page);

        GLib.SimpleActionGroup window_actions = new GLib.SimpleActionGroup();
        window_actions.add_action_entries(WINDOW_ACTIONS, this);
        insert_action_group(Action.Window.GROUP_NAME, window_actions);

        Application.Configuration config = this.application.config;
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
            Application.Configuration.FOLDER_LIST_PANE_HORIZONTAL_KEY,
            three_pane_view,
            "state"
        );
        config.bind(
            Application.Configuration.SINGLE_KEY_SHORTCUTS,
            single_key_shortucts,
            "state"
        );
        config.bind(
            Application.Configuration.STARTUP_NOTIFICATIONS_KEY,
            startup_notifications,
            "state"
        );

        this.delete_event.connect(on_delete);
    }

    private void on_close() {
        close();
    }

    private bool on_delete() {
        // Sync startup notification option with file state
        this.application.autostart.sync_with_config();
        return Gdk.EVENT_PROPAGATE;
    }

}
