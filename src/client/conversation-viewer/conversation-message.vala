/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an {@link Geary.RFC822.Message}.
 *
 * This view corresponds to {@link Geary.RFC822.Message}, displaying
 * both the message's headers and body. Any attachments and sub
 * messages are handled by {@link ConversationEmail}, which typically
 * embeds at least one instance of this class.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-message.ui")]
public class ConversationMessage : Gtk.Grid, Geary.BaseInterface {


    private const string FROM_CLASS = "geary-from";
    private const string MATCH_CLASS = "geary-match";
    private const string INTERNAL_ANCHOR_PREFIX = "geary:body#";
    private const string REPLACED_CID_TEMPLATE = "replaced_%02u@geary";
    private const string REPLACED_IMAGE_CLASS = "geary_replaced_inline_image";

    private const int MAX_PREVIEW_BYTES = Geary.Email.MAX_PREVIEW_BYTES;

    private const int SHOW_PROGRESS_TIMEOUT_MSEC = 1000;
    private const int HIDE_PROGRESS_TIMEOUT_MSEC = 1000;
    private const int PULSE_TIMEOUT_MSEC = 250;


    // Widget used to display sender/recipient email addresses in
    // message header Gtk.FlowBox instances.
    private class AddressFlowBoxChild : Gtk.FlowBoxChild {

        private const string PRIMARY_CLASS = "geary-primary";

        public enum Type { FROM, OTHER; }

        public Geary.RFC822.MailboxAddress address { get; private set; }

        private string search_value;

        public AddressFlowBoxChild(Geary.RFC822.MailboxAddress address,
                                   Type type = Type.OTHER) {
            this.address = address;
            this.search_value = address.to_searchable_string().casefold();

            // We use two label instances here when address has
            // distinct parts so we can dim the secondary part, if
            // any. Ideally, it would be just one label instance in
            // both cases, but we can't yet include CSS classes in
            // Pango markup. See Bug 766763.

            Gtk.Grid address_parts = new Gtk.Grid();

            bool is_spoofed = address.is_spoofed();
            if (is_spoofed) {
                Gtk.Image spoof_img = new Gtk.Image.from_icon_name(
                    "dialog-warning-symbolic", Gtk.IconSize.SMALL_TOOLBAR
                );
                this.set_tooltip_text(
                    _("This email address may have been forged")
                );
                address_parts.add(spoof_img);
            }

            Gtk.Label primary = new Gtk.Label(null);
            primary.ellipsize = Pango.EllipsizeMode.END;
            primary.set_halign(Gtk.Align.START);
            primary.get_style_context().add_class(PRIMARY_CLASS);
            if (type == Type.FROM) {
                primary.get_style_context().add_class(FROM_CLASS);
            }
            address_parts.add(primary);

            string display_address = address.to_address_display("", "");

            // Don't display the name if it looks spoofed, to reduce
            // chance of the user of being tricked by malware.
            if (address.has_distinct_name() && !is_spoofed) {
                primary.set_text(address.to_short_display());

                Gtk.Label secondary = new Gtk.Label(null);
                secondary.ellipsize = Pango.EllipsizeMode.END;
                secondary.set_halign(Gtk.Align.START);
                secondary.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
                secondary.set_text(display_address);
                address_parts.add(secondary);
            } else {
                primary.set_text(display_address);
            }

            // Update prelight state when mouse-overed.
            Gtk.EventBox events = new Gtk.EventBox();
            events.add_events(
                Gdk.EventMask.ENTER_NOTIFY_MASK |
                Gdk.EventMask.LEAVE_NOTIFY_MASK
            );
            events.set_visible_window(false);
            events.enter_notify_event.connect(on_prelight_in_event);
            events.leave_notify_event.connect(on_prelight_out_event);
            events.add(address_parts);

            add(events);
            set_halign(Gtk.Align.START);
            show_all();
        }

        public bool highlight_search_term(string term) {
            bool found = term in this.search_value;
            if (found) {
                get_style_context().add_class(MATCH_CLASS);
            } else {
                get_style_context().remove_class(MATCH_CLASS);
            }
            return found;
        }

        public void unmark_search_terms() {
            get_style_context().remove_class(MATCH_CLASS);
        }

        private bool on_prelight_in_event(Gdk.Event event) {
            set_state_flags(Gtk.StateFlags.PRELIGHT, false);
            return Gdk.EVENT_STOP;
        }

        private bool on_prelight_out_event(Gdk.Event event) {
            unset_state_flags(Gtk.StateFlags.PRELIGHT);
            return Gdk.EVENT_STOP;
        }

    }

    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;

    private const string ACTION_COPY_EMAIL = "copy_email";
    private const string ACTION_COPY_LINK = "copy_link";
    private const string ACTION_COPY_SELECTION = "copy_selection";
    private const string ACTION_OPEN_INSPECTOR = "open_inspector";
    private const string ACTION_OPEN_LINK = "open_link";
    private const string ACTION_SAVE_IMAGE = "save_image";
    private const string ACTION_SEARCH_FROM = "search_from";
    private const string ACTION_SELECT_ALL = "select_all";


    /** Box containing the preview and full header widgets.  */
    [GtkChild]
    internal Gtk.Grid summary;

    /** Box that InfoBar widgets should be added to. */
    [GtkChild]
    internal Gtk.Grid infobars;

    /** HTML view that displays the message body. */
    internal ConversationWebView web_view { get; private set; }

    private Geary.RFC822.MailboxAddress? primary_originator;

    [GtkChild]
    private Gtk.Image avatar;

    [GtkChild]
    private Gtk.Revealer compact_revealer;
    [GtkChild]
    private Gtk.Label compact_from;
    [GtkChild]
    private Gtk.Label compact_date;
    [GtkChild]
    private Gtk.Label compact_body;

    [GtkChild]
    private Gtk.Revealer header_revealer;
    [GtkChild]
    private Gtk.FlowBox from;
    [GtkChild]
    private Gtk.Label subject;
    private string subject_searchable = "";
    [GtkChild]
    private Gtk.Label date;

    [GtkChild]
    private Gtk.Grid sender_header;
    [GtkChild]
    private Gtk.FlowBox sender_address;

    [GtkChild]
    private Gtk.Grid reply_to_header;
    [GtkChild]
    private Gtk.FlowBox reply_to_addresses;

    [GtkChild]
    private Gtk.Grid to_header;
    [GtkChild]
    private Gtk.Grid cc_header;
    [GtkChild]
    private Gtk.Grid bcc_header;

    [GtkChild]
    private Gtk.Revealer body_revealer;
    [GtkChild]
    public Gtk.Grid body_container;
    [GtkChild]
    private Gtk.ProgressBar body_progress;

    [GtkChild]
    private Gtk.Popover link_popover;
    [GtkChild]
    private Gtk.Label good_link_label;
    [GtkChild]
    private Gtk.Label bad_link_label;

    [GtkChild]
    private Gtk.InfoBar remote_images_infobar;

    private Gtk.Widget? body_placeholder = null;

    // The web_view's context menu
    private Gtk.Menu? context_menu = null;

    // Menu models for creating the context menu
    private MenuModel context_menu_link;
    private MenuModel context_menu_email;
    private MenuModel context_menu_image;
    private MenuModel context_menu_main;
    private MenuModel context_menu_contact;
    private MenuModel? context_menu_inspector = null;

    // Address fields that can be search through
    private Gee.List<AddressFlowBoxChild> searchable_addresses =
        new Gee.LinkedList<AddressFlowBoxChild>();

    // Resource that have been loaded by the web view
    private Gee.Map<string,WebKit.WebResource> resources =
        new Gee.HashMap<string,WebKit.WebResource>();

    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    private int next_replaced_buffer_number = 0;

    // Is the view set to allow remote image loads?
    private bool is_loading_images;

    private int remote_resources_requested = 0;

    private int remote_resources_loaded = 0;

    // Timeouts for showing the progress bar and hiding it when
    // complete. The former is so that when loading cached images it
    // doesn't pop up and then go away immediately afterwards.
    private Geary.TimeoutManager show_progress_timeout = null;
    private Geary.TimeoutManager hide_progress_timeout = null;

    // Timer for pulsing progress bar
    private Geary.TimeoutManager progress_pulse;


    /** Fired when the user clicks a link in the email. */
    public signal void link_activated(string link);

    /** Fired when the user clicks a internal link in the email. */
    public signal void internal_link_activated(int y);

    /** Fired when the user requests remote images be loaded. */
    public signal void flag_remote_images();

    /** Fired when the user requests remote images be always loaded. */
    public signal void remember_remote_images();

    /** Fired when the user saves an inline displayed image. */
    public signal void save_image(string? uri, string? alt_text, Geary.Memory.Buffer buffer);

    /** Fired when the user activates a specific search shortcut. */
    public signal void search_activated(string operator, string value);


    /**
     * Constructs a new view from an email's headers and body.
     *
     * This method sets up most of the user interface for displaying
     * the message, but does not attempt any possibly long-running
     * loading processes.
     */
    public ConversationMessage.from_email(Geary.Email email,
                                          bool load_remote_images,
                                          Configuration config) {
        this(
            Util.Email.get_primary_originator(email),
            email.from,
            email.reply_to,
            email.sender,
            email.to,
            email.cc,
            email.bcc,
            email.date,
            email.subject,
            email.preview != null ? email.preview.buffer.get_valid_utf8() : null,
            load_remote_images,
            config
        );
    }

    /**
     * Constructs a new view from an RFC 822 message's headers and body.
     *
     * This method sets up most of the user interface for displaying
     * the message, but does not attempt any possibly long-running
     * loading processes.
     */
    public ConversationMessage.from_message(Geary.RFC822.Message message,
                                            bool load_remote_images,
                                            Configuration config) {
        this(
            Util.Email.get_primary_originator(message),
            message.from,
            message.reply_to,
            message.sender,
            message.to,
            message.cc,
            message.bcc,
            message.date,
            message.subject,
            message.get_preview(),
            load_remote_images,
            config
        );
    }

    private ConversationMessage(Geary.RFC822.MailboxAddress? primary_originator,
                                Geary.RFC822.MailboxAddresses? from,
                                Geary.RFC822.MailboxAddresses? reply_to,
                                Geary.RFC822.MailboxAddress? sender,
                                Geary.RFC822.MailboxAddresses? to,
                                Geary.RFC822.MailboxAddresses? cc,
                                Geary.RFC822.MailboxAddresses? bcc,
                                Geary.RFC822.Date? date,
                                Geary.RFC822.Subject? subject,
                                string? preview,
                                bool load_remote_images,
                                Configuration config) {
        base_ref();
        this.is_loading_images = load_remote_images;
        this.primary_originator = primary_originator;

        // Actions

        add_action(ACTION_COPY_EMAIL, true, VariantType.STRING)
            .activate.connect(on_copy_email_address);
        add_action(ACTION_COPY_LINK, true, VariantType.STRING)
            .activate.connect(on_copy_link);
        add_action(ACTION_COPY_SELECTION, false).activate.connect(() => {
                web_view.copy_clipboard();
            });
        add_action(ACTION_OPEN_INSPECTOR, Args.inspector).activate.connect(() => {
                this.web_view.get_inspector().show();
            });
        add_action(ACTION_OPEN_LINK, true, VariantType.STRING)
            .activate.connect(on_link_activated);
        add_action(ACTION_SAVE_IMAGE, true, new VariantType("(sms)"))
            .activate.connect(on_save_image);
        add_action(ACTION_SEARCH_FROM, true, VariantType.STRING)
            .activate.connect((param) => {
                search_activated("from", param.get_string());
            });
        add_action(ACTION_SELECT_ALL, true).activate.connect(() => {
                web_view.select_all();
            });

        insert_action_group("msg", message_actions);

        // Context menu

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menus.ui"
        );
        context_menu_link = (MenuModel) builder.get_object("context_menu_link");
        context_menu_email = (MenuModel) builder.get_object("context_menu_email");
        context_menu_image = (MenuModel) builder.get_object("context_menu_image");
        context_menu_main = (MenuModel) builder.get_object("context_menu_main");
        context_menu_contact = (MenuModel) builder.get_object("context_menu_contact");
        if (Args.inspector) {
            context_menu_inspector =
                (MenuModel) builder.get_object("context_menu_inspector");
        }

        // Compact headers

        // Translators: This is displayed in place of the from address
        // when the message has no from address.
        string empty_from = _("No sender");

        this.compact_from.set_text(format_originator_compact(from, empty_from));
        this.compact_from.get_style_context().add_class(FROM_CLASS);

        string date_text = "";
        string date_tooltip = "";
        if (date != null) {
            date_text = Date.pretty_print(
                date.value, config.clock_format
            );
            date_tooltip = Date.pretty_print_verbose(
                date.value, config.clock_format
            );
        }
        this.compact_date.set_text(date_text);
        this.compact_date.set_tooltip_text(date_tooltip);

        if (preview != null) {
            string clean_preview = preview;
            if (preview.length > MAX_PREVIEW_BYTES) {
                clean_preview = Geary.String.safe_byte_substring(
                    preview, MAX_PREVIEW_BYTES
                );
                // Add an ellipsis in case the view is wider is wider than
                // the text
                clean_preview += "…";
            }
            this.compact_body.set_text(clean_preview);
        }

        // Full headers

        fill_originator_addresses(from, reply_to, sender, empty_from);

        this.date.set_text(date_text);
        this.date.set_tooltip_text(date_tooltip);
        if (subject != null) {
            this.subject.set_text(subject.value);
            this.subject.set_visible(true);
            this.subject_searchable = subject.value.casefold();
        }
        fill_header_addresses(this.to_header, to);
        fill_header_addresses(this.cc_header, cc);
        fill_header_addresses(this.bcc_header, bcc);


        // Web view

        this.web_view = new ConversationWebView(config);
        if (load_remote_images) {
            this.web_view.allow_remote_image_loading();
        }
        this.web_view.context_menu.connect(on_context_menu);
        this.web_view.deceptive_link_clicked.connect(on_deceptive_link_clicked);
        this.web_view.link_activated.connect((link) => {
                on_link_activated(new GLib.Variant("s", link));
            });
        this.web_view.mouse_target_changed.connect(on_mouse_target_changed);
        this.web_view.notify["is-loading"].connect(on_is_loading_notify);
        this.web_view.resource_load_started.connect(on_resource_load_started);
        this.web_view.remote_image_load_blocked.connect(() => {
                this.remote_images_infobar.show();
            });
        this.web_view.selection_changed.connect(on_selection_changed);
        this.web_view.set_hexpand(true);
        this.web_view.set_vexpand(true);
        this.web_view.show();

        this.body_container.set_has_tooltip(true); // Used to show link URLs
        this.body_container.add(this.web_view);
        this.show_progress_timeout = new Geary.TimeoutManager.milliseconds(
            SHOW_PROGRESS_TIMEOUT_MSEC, this.on_show_progress_timeout
        );
        this.hide_progress_timeout = new Geary.TimeoutManager.milliseconds(
            HIDE_PROGRESS_TIMEOUT_MSEC, this.on_hide_progress_timeout
        );

        this.progress_pulse = new Geary.TimeoutManager.milliseconds(
            PULSE_TIMEOUT_MSEC, this.body_progress.pulse
        );
        this.progress_pulse.repetition = FOREVER;
    }

    ~ConversationMessage() {
        base_unref();
    }

    public override void destroy() {
        this.show_progress_timeout.reset();
        this.hide_progress_timeout.reset();
        this.progress_pulse.reset();
        this.resources.clear();
        this.searchable_addresses.clear();
        base.destroy();
    }

    /**
     * Shows the complete message and hides the compact headers.
     */
    public void show_message_body(bool include_transitions=true) {
        set_revealer(this.compact_revealer, false, include_transitions);
        set_revealer(this.header_revealer, true, include_transitions);
        set_revealer(this.body_revealer, true, include_transitions);
    }

    /**
     * Hides the complete message and shows the compact headers.
     */
    public void hide_message_body() {
        compact_revealer.set_reveal_child(true);
        header_revealer.set_reveal_child(false);
        body_revealer.set_reveal_child(false);
    }

    /** Shows a panel when an email is being loaded. */
    public void show_loading_pane() {
        Components.PlaceholderPane pane = new Components.PlaceholderPane();
        pane.icon_name = "content-loading-symbolic";
        pane.title = "";
        pane.subtitle = "";

        // Don't want to break the announced freeze for 0.13, so just
        // hope the icon gets the message across for now and replace
        // them with the ones below for 0.14.

        // Translators: Title label for placeholder when multiple
        // an error occurs loading a message for display.
        //pane.title = _("A problem occurred");
        // Translators: Sub-title label for placeholder when multiple
        // an error occurs loading a message for display.
        //pane.subtitle = _(
        //    "This email cannot currently be displayed"
        //);
        show_placeholder_pane(pane);
        start_progress_pulse();
    }

    /** Shows an error panel when email loading failed. */
    public void show_load_error_pane() {
        Components.PlaceholderPane pane = new Components.PlaceholderPane();
        pane.icon_name = "network-error-symbolic";
        pane.title = "";
        pane.subtitle = "";

        // Don't want to break the announced freeze for 0.13, so just
        // hope the icon gets the message across for now and replace
        // them with the ones below for 0.14.

        // Translators: Title label for placeholder when multiple
        // an error occurs loading a message for display.
        //pane.title = _("A problem occurred");
        // Translators: Sub-title label for placeholder when multiple
        // an error occurs loading a message for display.
        //pane.subtitle = _(
        //    "This email cannot currently be displayed"
        //);
        show_placeholder_pane(pane);
        stop_progress_pulse();
    }

    /** Shows an error panel when offline. */
    public void show_offline_pane() {
        show_message_body(true);
        Components.PlaceholderPane pane = new Components.PlaceholderPane();
        pane.icon_name = "network-offline-symbolic";
        pane.title = "";
        pane.subtitle = "";

        // Don't want to break the announced freeze for 0.13, so just
        // hope the icon gets the message across for now and replace
        // them with the ones below for 0.14.

        // // Translators: Title label for placeholder when loading a
        // // message for display but the account is offline.
        // pane.title = _("Offline");
        // // Translators: Sub-title label for placeholder when loading a
        // // message for display but the account is offline.
        // pane.subtitle = _(
        //     "This email will be downloaded when reconnected to the Internet"
        // );
        show_placeholder_pane(pane);
        stop_progress_pulse();
    }

    /** Shows and initialises the progress meter. */
    public void start_progress_loading( ) {
        this.progress_pulse.reset();
        this.body_progress.fraction = 0.1;
        this.show_progress_timeout.start();
        this.hide_progress_timeout.reset();
    }

    /** Hides the progress meter. */
    public void stop_progress_loading( ) {
        this.body_progress.fraction = 1.0;
        this.show_progress_timeout.reset();
        this.hide_progress_timeout.start();
    }

    /** Shows and starts pulsing the progress meter. */
    public void start_progress_pulse() {
        this.body_progress.show();
        this.progress_pulse.start();
    }

    /** Hides and stops pulsing the progress meter. */
    public void stop_progress_pulse() {
        this.body_progress.hide();
        this.progress_pulse.reset();
    }

    /**
     * Starts loading the avatar for the message's sender.
     */
    public async void load_avatar(Application.AvatarStore loader,
                                  GLib.Cancellable load_cancelled)
        throws GLib.Error {
        if (load_cancelled.is_cancelled()) {
            throw new GLib.IOError.CANCELLED("Conversation load cancelled");
        }

        // We occasionally get crashes calling as below
        // Gtk.Image.get_pixel_size() when the image is null. There's
        // perhaps some race going on there. So we need to hard-code
        // the size here and keep it in sync with
        // ui/conversation-message.ui. :(
        const int PIXEL_SIZE = 48;
        if (this.primary_originator != null) {
            int window_scale = get_scale_factor();
            //int pixel_size = this.avatar.get_pixel_size() * window_scale;
            int pixel_size = PIXEL_SIZE * window_scale;
            Gdk.Pixbuf? avatar_buf = yield loader.load(
                this.primary_originator, pixel_size, load_cancelled
            );
            if (avatar_buf != null) {
                this.avatar.set_from_surface(
                    Gdk.cairo_surface_create_from_pixbuf(
                        avatar_buf, window_scale, get_window()
                    )
                );
            }
        }
    }

    /**
     * Starts loading the message body in the HTML view.
     */
    public async void load_message_body(Geary.RFC822.Message message,
                                        GLib.Cancellable load_cancelled)
        throws GLib.Error {
        if (load_cancelled.is_cancelled()) {
            throw new GLib.IOError.CANCELLED("Conversation load cancelled");
        }

        show_placeholder_pane(null);

        string? body_text = null;
        try {
            body_text = (message.has_html_body())
                ? message.get_html_body(inline_image_replacer)
                : message.get_plain_body(true, inline_image_replacer);
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }

        load_cancelled.cancelled.connect(() => { web_view.stop_loading(); });
        this.web_view.load_html(body_text ?? "");
    }

    /**
     * Highlights user search terms in the message view.
     *
     * Highlighting includes both in the message headers, and the
     * mesage body. returns the number of matching search terms.
     */
    public async uint highlight_search_terms(Gee.Set<string> search_matches,
                                             GLib.Cancellable cancellable)
        throws GLib.IOError.CANCELLED {
        uint headers_found = 0;
        uint webkit_found = 0;
        foreach(string raw_match in search_matches) {
            string match = raw_match.casefold();

            if (this.subject_searchable.contains(match)) {
                this.subject.get_style_context().add_class(MATCH_CLASS);
                ++headers_found;
            } else {
                this.subject.get_style_context().remove_class(MATCH_CLASS);
            }

            foreach (AddressFlowBoxChild address in this.searchable_addresses) {
                if (address.highlight_search_term(match)) {
                    ++headers_found;
                }
            }
        }

        webkit_found += yield this.web_view.highlight_search_terms(
            search_matches, cancellable
        );
        return headers_found + webkit_found;
    }

    /**
     * Disables highlighting of any search terms in the message view.
     */
    public void unmark_search_terms() {
        foreach (AddressFlowBoxChild address in this.searchable_addresses) {
            address.unmark_search_terms();
        }
        this.web_view.unmark_search_terms();
    }

    private SimpleAction add_action(string name, bool enabled, VariantType? type = null) {
        SimpleAction action = new SimpleAction(name, type);
        action.set_enabled(enabled);
        message_actions.add_action(action);
        return action;
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action =
            this.message_actions.lookup_action(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private Menu set_action_param_value(MenuModel existing, Variant value) {
        Menu menu = new Menu();
        for (int i = 0; i < existing.get_n_items(); i++) {
            MenuItem item = new MenuItem.from_model(existing, i);
            Variant action = item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            item.set_action_and_target_value(action.get_string(), value);
            menu.append_item(item);
        }
        return menu;
    }

    private Menu set_action_param_strings(MenuModel existing,
                                          Gee.Map<string,string> values) {
        Menu menu = new Menu();
        for (int i = 0; i < existing.get_n_items(); i++) {
            MenuItem item = new MenuItem.from_model(existing, i);
            Variant action = item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            string fq_name = action.get_string();
            string name = fq_name.substring(fq_name.index_of(".") + 1);
            item.set_action_and_target(
                fq_name, VariantType.STRING.dup_string(), values[name]
            );
            menu.append_item(item);
        }
        return menu;
    }

    private string format_originator_compact(Geary.RFC822.MailboxAddresses? from,
                                             string empty_from_text) {
        string text = "";
        if (from != null && from.size > 0) {
            int i = 0;
            Gee.List<Geary.RFC822.MailboxAddress> list = from.get_all();
            foreach (Geary.RFC822.MailboxAddress addr in list) {
                text += addr.to_short_display();

                if (++i < list.size)
                    // Translators: This separates multiple 'from'
                    // addresses in the compact header for a message.
                    text += _(", ");
            }
        } else {
            text = empty_from_text;
        }

        return text;
    }

    private void fill_originator_addresses(Geary.RFC822.MailboxAddresses? from,
                                           Geary.RFC822.MailboxAddresses? reply_to,
                                           Geary.RFC822.MailboxAddress? sender,
                                           string empty_from_text)  {
        // Show any From header addresses
        if (from != null && from.size > 0) {
            foreach (Geary.RFC822.MailboxAddress address in from) {
                AddressFlowBoxChild child = new AddressFlowBoxChild(
                    address, AddressFlowBoxChild.Type.FROM
                );
                this.searchable_addresses.add(child);
                this.from.add(child);
            }
        } else {
            Gtk.Label label = new Gtk.Label(null);
            label.set_text(empty_from_text);

            Gtk.FlowBoxChild child = new Gtk.FlowBoxChild();
            child.add(label);
            child.set_halign(Gtk.Align.START);
            child.show_all();
            this.from.add(child);
        }

        // Show the Sender header addresses if present, but only if
        // not already in the From header.
        if (sender != null &&
            (from == null || !from.contains_normalized(sender.address))) {
            AddressFlowBoxChild child = new AddressFlowBoxChild(sender);
            this.searchable_addresses.add(child);
            this.sender_header.show();
            this.sender_address.add(child);
        }

        // Show any Reply-To header addresses if present, but only if
        // each is not already in the From header.
        if (reply_to != null) {
            foreach (Geary.RFC822.MailboxAddress address in reply_to) {
                if (from == null || !from.contains_normalized(address.address)) {
                    AddressFlowBoxChild child = new AddressFlowBoxChild(address);
                    this.searchable_addresses.add(child);
                    this.reply_to_addresses.add(child);
                    this.reply_to_header.show();
                }
            }
        }
    }

    private void fill_header_addresses(Gtk.Grid header,
                                       Geary.RFC822.MailboxAddresses? addresses) {
        if (addresses != null && addresses.size > 0) {
            Gtk.FlowBox box = header.get_children().nth(0).data as Gtk.FlowBox;
            if (box != null) {
                foreach (Geary.RFC822.MailboxAddress address in addresses) {
                    AddressFlowBoxChild child = new AddressFlowBoxChild(address);
                    this.searchable_addresses.add(child);
                    box.add(child);
                }
            }
            header.set_visible(true);
        }
    }

    // This delegate is called from within
    // Geary.RFC822.Message.get_body while assembling the plain or
    // HTML document when a non-text MIME part is encountered within a
    // multipart/mixed container.  If this returns null, the MIME part
    // is dropped from the final returned document; otherwise, this
    // returns HTML that is placed into the document in the position
    // where the MIME part was found
    private string? inline_image_replacer(Geary.RFC822.Part part) {
        Geary.Mime.ContentType content_type = part.get_effective_content_type();
        if (content_type.media_type != "image" ||
            !this.web_view.can_show_mime_type(content_type.to_string())) {
            debug("Not displaying %s inline: unsupported Content-Type",
                  content_type.to_string());
            return null;
        }

        string? id = part.content_id;
        if (id == null) {
            id = REPLACED_CID_TEMPLATE.printf(this.next_replaced_buffer_number++);
        }

        try {
            this.web_view.add_internal_resource(id, part.write_to_buffer());
        } catch (Geary.RFC822Error err) {
            debug("Failed to get inline buffer: %s", err.message);
            return null;
        }

        // Translators: This string is used as the HTML IMG ALT
        // attribute value when displaying an inline image in an email
        // that did not specify a file name. E.g. <IMG ALT="Image" ...
        string UNKNOWN_FILENAME_ALT_TEXT = _("Image");
        string clean_filename = Geary.HTML.escape_markup(
            part.get_clean_filename() ?? UNKNOWN_FILENAME_ALT_TEXT
        );

        return "<img alt=\"%s\" class=\"%s\" src=\"%s%s\" />".printf(
            clean_filename,
            REPLACED_IMAGE_CLASS,
            ClientWebView.CID_URL_PREFIX,
            Geary.HTML.escape_markup(id)
        );
    }

    private void show_images(bool remember) {
        start_progress_loading();
        this.is_loading_images = true;
        this.remote_resources_requested = 0;
        this.remote_resources_loaded = 0;
        this.web_view.load_remote_images();
        if (remember) {
            flag_remote_images();
        }
    }

    private void show_placeholder_pane(Gtk.Widget? placeholder) {
        if (this.body_placeholder != null) {
            this.body_placeholder.hide();
            this.body_container.remove(this.body_placeholder);
            this.body_placeholder = null;
        }

        if (placeholder != null) {
            this.body_placeholder = placeholder;
            this.web_view.hide();
            this.body_container.add(placeholder);
            show_message_body(true);
        } else {
            this.web_view.show();
        }
    }

    private inline void set_revealer(Gtk.Revealer revealer,
                                     bool expand,
                                     bool use_transition) {
        Gtk.RevealerTransitionType transition = revealer.get_transition_type();
        if (!use_transition) {
            revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        revealer.set_reveal_child(expand);
        revealer.set_transition_type(transition);
    }

    private void on_show_progress_timeout() {
        if (this.body_progress.fraction < 0.99) {
            this.progress_pulse.reset();
            this.body_progress.show();
        }
    }

    private void on_hide_progress_timeout() {
        this.progress_pulse.reset();
        this.body_progress.hide();
    }

    private void on_is_loading_notify() {
        if (this.web_view.is_loading) {
            start_progress_loading();
        } else {
            stop_progress_loading();
        }
    }

    private void on_resource_load_started(WebKit.WebView view,
                                          WebKit.WebResource res,
                                          WebKit.URIRequest req) {
        // Cache the resource to allow images to be saved
        this.resources[res.get_uri()] = res;

        // We only want to show the body loading progress meter if we
        // are actually loading some images, so do it here rather than
        // in on_is_loading_notify.
        this.remote_resources_requested++;
        res.finished.connect(() => {
                this.remote_resources_loaded++;
                this.body_progress.fraction = (
                    (float) this.remote_resources_loaded /
                    (float) this.remote_resources_requested
                );

                if (this.remote_resources_loaded ==
                    this.remote_resources_requested) {
                    stop_progress_loading();
                }
            });
    }

    [GtkCallback]
    private void on_address_box_child_activated(Gtk.FlowBox box,
                                                Gtk.FlowBoxChild child) {
        AddressFlowBoxChild address_child = child as AddressFlowBoxChild;
        if (address_child != null) {
            address_child.set_state_flags(Gtk.StateFlags.ACTIVE, false);

            Geary.RFC822.MailboxAddress address = address_child.address;
            Gee.Map<string,string> values = new Gee.HashMap<string,string>();
            values[ACTION_OPEN_LINK] =
                Geary.ComposedEmail.MAILTO_SCHEME + address.address;
                values[ACTION_COPY_EMAIL] = address.to_full_display();
            values[ACTION_SEARCH_FROM] = address.address;

            Menu model = new Menu();
            model.append_section(
                null, set_action_param_strings(this.context_menu_email, values)
            );
            model.append_section(
                null, set_action_param_strings(this.context_menu_contact, values)
            );
            Gtk.Popover popover = new Gtk.Popover.from_model(child, model);
            popover.set_position(Gtk.PositionType.BOTTOM);
            popover.closed.connect(() => {
                    address_child.unset_state_flags(Gtk.StateFlags.ACTIVE);
                });
            popover.show();
        }
    }

    private bool on_context_menu(WebKit.WebView view,
                                 WebKit.ContextMenu context_menu,
                                 Gdk.Event event,
                                 WebKit.HitTestResult hit_test) {
        if (this.context_menu != null) {
            this.context_menu.detach();
        }

        // Build a new context menu every time the user clicks because
        // at the moment under GTK+3.20 it's far easier to selectively
        // build a new menu model from pieces as we do here, then to
        // have a single menu model and disable the parts we don't
        // need.
        Menu model = new Menu();

        if (hit_test.context_is_link()) {
            string link_url = hit_test.get_link_uri();
            MenuModel link_menu =
                link_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)
                ? context_menu_email
                : context_menu_link;
            model.append_section(
                null,
                set_action_param_value(
                    link_menu, new Variant.string(link_url)
                )
            );
        }

        if (hit_test.context_is_image()) {
            string uri = hit_test.get_image_uri();
            set_action_enabled(ACTION_SAVE_IMAGE, this.resources.has_key(uri));
            model.append_section(
                null,
                set_action_param_value(
                    context_menu_image,
                    new Variant.tuple({
                            new Variant.string(uri),
                            new Variant("ms", hit_test.get_link_label()),
                        })
                )
            );
        }

        model.append_section(null, context_menu_main);

        if (context_menu_inspector != null) {
            model.append_section(null, context_menu_inspector);
        }

        this.context_menu = new Gtk.Menu.from_model(model);
        this.context_menu.attach_to_widget(this, null);
        this.context_menu.popup_at_pointer(event);

        return true;
    }

    private void on_mouse_target_changed(WebKit.WebView web_view,
                                         WebKit.HitTestResult hit_test,
                                         uint modifiers) {
        this.body_container.set_tooltip_text(
            hit_test.context_is_link() ? hit_test.get_link_uri() : null
        );
        this.body_container.trigger_tooltip_query();
    }

    // Check for possible phishing links, displays a popover if found.
    // If not, lets it go through to the default handler.
    private void on_deceptive_link_clicked(ConversationWebView.DeceptiveText reason,
                                           string text,
                                           string href,
                                           Gdk.Rectangle location) {
        string text_href = text;
        if (Uri.parse_scheme(text_href) == null) {
            text_href = "http://" + text_href;
        }
        string text_label = Soup.URI.decode(text_href);

        string anchor_href = href;
        if (Uri.parse_scheme(anchor_href) == null) {
            anchor_href = "http://" + anchor_href;
        }
        string anchor_label = Soup.URI.decode(anchor_href);

        // Escape text and especially URLs since we got them from the
        // HREF, and Gtk.Label.set_markup is a strict parser.
        good_link_label.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", text_href, text_label)
        );
        bad_link_label.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", anchor_href, anchor_label)
        );
        link_popover.set_relative_to(this.web_view);
        link_popover.set_pointing_to(location);
        link_popover.show();
    }

    [GtkCallback]
    private bool on_link_popover_activated() {
        this.link_popover.hide();
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_selection_changed(bool has_selection) {
        set_action_enabled(ACTION_COPY_SELECTION, has_selection);
    }

    [GtkCallback]
    private void on_remote_images_response(Gtk.InfoBar info_bar, int response_id) {
        switch (response_id) {
        case 1:
            // Show images for the message
            show_images(true);
            break;
        case 2:
            // Show images for sender
            show_images(false);
            remember_remote_images();
            break;
        default:
            // Pass
            break;
        }

        remote_images_infobar.hide();
    }

    private void on_copy_link(Variant? param) {
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(param.get_string(), -1);
        clipboard.store();
    }

    private void on_copy_email_address(Variant? param) {
        string value = param.get_string();
        if (value.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            value = value.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1);
        }
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(value, -1);
        clipboard.store();
    }

    private void on_save_image(Variant? param) {
        string cid_url = param.get_child_value(0).get_string();

        string? alt_text = null;
        Variant? alt_maybe = param.get_child_value(1).get_maybe();
        if (alt_maybe != null) {
            alt_text = alt_maybe.get_string();
        }
        WebKit.WebResource response = this.resources.get(cid_url);
        response.get_data.begin(null, (obj, res) => {
                try {
                    uint8[] data = response.get_data.end(res);
                    save_image(response.get_uri(),
                               alt_text,
                               new Geary.Memory.ByteBuffer(data, data.length));
                } catch (Error err) {
                    debug(
                        "Failed to get image data from web view: %s",
                        err.message
                    );
                }
            });
    }

    private void on_link_activated(GLib.Variant? param) {
        string link = param.get_string();

        if (link.has_prefix(INTERNAL_ANCHOR_PREFIX)) {
            long start = INTERNAL_ANCHOR_PREFIX.length;
            long end = link.length;
            string anchor_body = link.substring(start, end - start);
            this.web_view.get_anchor_target_y.begin(anchor_body, (obj, res) => {
                    try {
                        int y = this.web_view.get_anchor_target_y.end(res);
                        if (y > 0) {
                            internal_link_activated(y);
                        } else {
                            debug("Failed to get anchor destination");
                        }
                    } catch (GLib.Error err) {
                        debug("Failed to get anchor destination");
                    }
                });
        } else {
            link_activated(link);
        }
    }

}
