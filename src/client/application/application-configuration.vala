/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Provides properties to access application GSettings values.
 */
public class Application.Configuration : Geary.BaseObject {


    public const string ASK_OPEN_ATTACHMENT_KEY = "ask-open-attachment";
    public const string AUTOSELECT_KEY = "autoselect";
    public const string BRIEF_NOTIFICATION_DURATION = "brief-notification-duration";
    public const string COMPOSER_WINDOW_SIZE_KEY = "composer-window-size";
    public const string COMPOSE_AS_HTML_KEY = "compose-as-html";
    public const string CONVERSATION_VIEWER_ZOOM_KEY = "conversation-viewer-zoom";
    public const string DISPLAY_PREVIEW_KEY = "display-preview";
    public const string UNSET_HTML_COLORS = "unset-html-colors";
    public const string FORMATTING_TOOLBAR_VISIBLE = "formatting-toolbar-visible";
    public const string OPTIONAL_PLUGINS = "optional-plugins";
    public const string SEARCH_STRATEGY_KEY = "search-strategy";
    public const string SINGLE_KEY_SHORTCUTS = "single-key-shortcuts";
    public const string SPELL_CHECK_LANGUAGES = "spell-check-languages";
    public const string SPELL_CHECK_VISIBLE_LANGUAGES = "spell-check-visible-languages";
    public const string RUN_IN_BACKGROUND_KEY = "run-in-background";
    public const string UNDO_SEND_DELAY = "undo-send-delay";
    public const string WINDOW_HEIGHT_KEY = "window-height";
    public const string WINDOW_MAXIMIZE_KEY = "window-maximize";
    public const string WINDOW_WIDTH_KEY = "window-width";
    public const string IMAGES_TRUSTED_DOMAINS = "images-trusted-domains";


    public enum DesktopEnvironment {
        UNKNOWN = 0,
        UNITY;
    }


    // is_installed: set to true if installed, else false.
    // schema_dir: MUST be set if not installed. Directory where GSettings schema is located.
    public static void init(bool is_installed, string? schema_dir = null) {
        if (!is_installed) {
            assert(schema_dir != null);
            // If not installed, set an environment variable pointing to where the GSettings schema
            // is to be found.
            GLib.Environment.set_variable("GSETTINGS_SCHEMA_DIR", schema_dir, true);
        }
    }


    public Settings settings { get; private set; }
    public Settings gnome_interface { get; private set; }

    // Can be set as an arguments
    public bool enable_debug { get; set; default = false; }

    // Can be set as an arguments
    public bool enable_inspector { get; set; default = false; }

    // Can be set as an arguments
    public bool revoke_certs { get; set; default = false; }

    public DesktopEnvironment desktop_environment {
        get {
            string? xdg_current_desktop = Environment.get_variable("XDG_CURRENT_DESKTOP");
            if (xdg_current_desktop != null && xdg_current_desktop.has_prefix("Unity")) {
                return DesktopEnvironment.UNITY;
            } else {
                return DesktopEnvironment.UNKNOWN;
            }
        }
    }

    public int window_width {
        get { return settings.get_int(WINDOW_WIDTH_KEY); }
    }

    public int window_height {
        get { return settings.get_int(WINDOW_HEIGHT_KEY); }
    }

    public bool window_maximize {
        get { return settings.get_boolean(WINDOW_MAXIMIZE_KEY); }
    }

    public bool formatting_toolbar_visible {
        get { return settings.get_boolean(FORMATTING_TOOLBAR_VISIBLE); }
        set { settings.set_boolean(FORMATTING_TOOLBAR_VISIBLE, value); }
    }

    public bool autoselect {
        get { return settings.get_boolean(AUTOSELECT_KEY); }
    }

    public bool display_preview {
        get { return settings.get_boolean(DISPLAY_PREVIEW_KEY); }
    }

    public bool unset_html_colors {
        get { return settings.get_boolean(UNSET_HTML_COLORS); }
    }

    public bool single_key_shortcuts { get; set; default = false; }

    public bool run_in_background {
        get { return settings.get_boolean(RUN_IN_BACKGROUND_KEY); }
        set { set_boolean(RUN_IN_BACKGROUND_KEY, value); }
    }

    private const string CLOCK_FORMAT_KEY = "clock-format";
    public Util.Date.ClockFormat clock_format {
        get {
            if (gnome_interface.get_string(CLOCK_FORMAT_KEY) == "12h")
                return Util.Date.ClockFormat.TWELVE_HOURS;
            else
                return Util.Date.ClockFormat.TWENTY_FOUR_HOURS;
        }
    }

    public bool ask_open_attachment {
        get { return settings.get_boolean(ASK_OPEN_ATTACHMENT_KEY); }
        set { set_boolean(ASK_OPEN_ATTACHMENT_KEY, value); }
    }

    public bool compose_as_html {
        get { return settings.get_boolean(COMPOSE_AS_HTML_KEY); }
        set { set_boolean(COMPOSE_AS_HTML_KEY, value); }
    }

    public double conversation_viewer_zoom {
        get { return settings.get_double(CONVERSATION_VIEWER_ZOOM_KEY); }
        set { settings.set_double(CONVERSATION_VIEWER_ZOOM_KEY, value); }
    }

    /** The number of seconds to wait before sending an email. */
    public int undo_send_delay {
        get { return settings.get_int(UNDO_SEND_DELAY); }
    }

    /** The number of seconds for which brief notifications should be displayed. */
    public int brief_notification_duration {
        get { return settings.get_int(BRIEF_NOTIFICATION_DURATION); }
    }

    // Creates a configuration object.
    public Configuration(string schema_id) {
        // Start GSettings.
        settings = new Settings(schema_id);
        gnome_interface = new Settings("org.gnome.desktop.interface");

        Util.Migrate.old_app_config(settings);

        this.bind(SINGLE_KEY_SHORTCUTS, this, SINGLE_KEY_SHORTCUTS);
    }

    public void bind(string key, Object object, string property,
        SettingsBindFlags flags = GLib.SettingsBindFlags.DEFAULT) {
        settings.bind(key, object, property, flags);
    }

    public void bind_with_mapping(string key, Object object, string property,
        SettingsBindGetMappingShared get_mapping,
        SettingsBindSetMappingShared set_mapping,
        SettingsBindFlags flags = GLib.SettingsBindFlags.DEFAULT) {
        settings.bind_with_mapping(
            key, object, property, flags,
            get_mapping, set_mapping, null, null
        );
    }

    private void set_boolean(string name, bool value) {
        if (!settings.set_boolean(name, value))
            message("Unable to set configuration value %s = %s", name, value.to_string());
    }

    /** Returns the saved size of the composer window. */
    public int[] get_composer_window_size() {
        int[] size = new int[2];
        var s = this.settings.get_value(COMPOSER_WINDOW_SIZE_KEY);
        if (s.n_children () == 2) {
            size = { (int) s.get_child_value(0), (int) s.get_child_value(1)};
        } else {
            size = {-1,-1};
        }
        return size;
    }

    /** Sets the saved size of the composer window. */
    public void set_composer_window_size(int[] value) {
        this.settings.set_value(COMPOSER_WINDOW_SIZE_KEY, value);
    }

    /** Returns list of trusted domains for which images loading is allowed. */
    public string[] get_images_trusted_domains() {
        return this.settings.get_strv(IMAGES_TRUSTED_DOMAINS);
    }

    /** Sets list of trusted domains for which images loading is allowed. */
    public void set_images_trusted_domains(string[] value) {
        this.settings.set_strv(IMAGES_TRUSTED_DOMAINS, value);
    }

    /** Adds domain to trusted list for which images loading is allowed. */
    public void add_images_trusted_domain(string domain) {
        var domains = get_images_trusted_domains();
        domains += domain;
        set_images_trusted_domains(domains);
    }

    /** Removes domain from trusted for which images loading is allowed. */
    public void remove_images_trusted_domain(string domain) {
        var domains = get_images_trusted_domains();
        string[] new_domains = {};
        foreach (var _domain in domains) {
            if (domain != _domain)
                new_domains += _domain;
        }
        set_images_trusted_domains(new_domains);
    }

    /**
     * Returns list of optional plugins to load by default
     */
    public string[] get_optional_plugins() {
        return this.settings.get_strv(OPTIONAL_PLUGINS);
    }

    /**
     * Sets the list of optional plugins to load by default
     */
    public void set_optional_plugins(string[] value) {
        this.settings.set_strv(OPTIONAL_PLUGINS, value);
    }

    /**
     * Returns enabled spell checker languages.
     *
     * This specifies the languages used for spell checking by the
     * client. By default, the set will contain languages based on
     * environment variables.
     *
     * @see Util.I18n.get_user_preferred_languages
     */
    public string[] get_spell_check_languages() {
        GLib.Variant? value = this.settings.get_value(
            SPELL_CHECK_LANGUAGES
        ).get_maybe();
        string[] langs = (value != null)
            ? value.get_strv()
            : Util.I18n.get_user_preferred_languages();
        return langs;
    }

    /**
     * Sets enabled spell checker languages.
     *
     * This specifies the languages used for spell checking by the
     * client. By default, the set will contain languages based on
     * environment variables.
     *
     * @see Util.I18n.get_user_preferred_languages
     */
    public void set_spell_check_languages(string[] value) {
        this.settings.set_value(
            SPELL_CHECK_LANGUAGES,
            new GLib.Variant.maybe(null, new GLib.Variant.strv(value))
        );
    }

    /**
     * Returns visible spell checker languages.
     *
     * This is the list of languages shown when selecting languages to
     * be used for spell checking.
     */
    public string[] get_spell_check_visible_languages() {
        return this.settings.get_strv(SPELL_CHECK_VISIBLE_LANGUAGES);
    }

    /**
     * Sets visible spell checker languages.
     *
     * This is the list of languages shown when selecting languages to
     * be used for spell checking.
     */
    public void set_spell_check_visible_languages(string[] value) {
        this.settings.set_strv(SPELL_CHECK_VISIBLE_LANGUAGES, value);
    }

    public Geary.SearchQuery.Strategy get_search_strategy() {
        switch (settings.get_string(SEARCH_STRATEGY_KEY).down()) {
            case "exact":
                return Geary.SearchQuery.Strategy.EXACT;

            case "aggressive":
                return Geary.SearchQuery.Strategy.AGGRESSIVE;

            case "horizon":
                return Geary.SearchQuery.Strategy.HORIZON;

            case "conservative":
            default:
                return Geary.SearchQuery.Strategy.CONSERVATIVE;
        }
    }

    public void set_search_strategy(Geary.SearchQuery.Strategy strategy) {
        switch (strategy) {
            case Geary.SearchQuery.Strategy.EXACT:
                settings.set_string(SEARCH_STRATEGY_KEY, "exact");
            break;

            case Geary.SearchQuery.Strategy.AGGRESSIVE:
                settings.set_string(SEARCH_STRATEGY_KEY, "aggressive");
            break;

            case Geary.SearchQuery.Strategy.HORIZON:
                settings.set_string(SEARCH_STRATEGY_KEY, "horizon");
            break;

            case Geary.SearchQuery.Strategy.CONSERVATIVE:
            default:
                settings.set_string(SEARCH_STRATEGY_KEY, "conservative");
            break;
        }
    }
}

