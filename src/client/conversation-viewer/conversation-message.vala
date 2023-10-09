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
    private const string SPOOF_CLASS = "geary-spoofed";
    private const string INTERNAL_ANCHOR_PREFIX = "geary:body#";
    private const string REPLACED_CID_TEMPLATE = "replaced_%02u@geary";
    private const string REPLACED_IMAGE_CLASS = "geary_replaced_inline_image";

    private const string MAILTO_URI_PREFIX = "mailto:";


    private const int MAX_PREVIEW_BYTES = Geary.Email.MAX_PREVIEW_BYTES;

    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;

    private const string ACTION_CONVERSATION_NEW = "conversation-new";
    private const string ACTION_COPY_EMAIL = "copy-email";
    private const string ACTION_COPY_LINK = "copy-link";
    private const string ACTION_COPY_SELECTION = "copy-selection";
    private const string ACTION_OPEN_INSPECTOR = "open-inspector";
    private const string ACTION_OPEN_LINK = "open-link";
    private const string ACTION_SAVE_IMAGE = "save-image";
    private const string ACTION_SELECT_ALL = "select-all";
    private const string ACTION_SHOW_IMAGES_MESSAGE = "show-images-message";
    private const string ACTION_SHOW_IMAGES_SENDER = "show-images-sender";
    private const string ACTION_SHOW_IMAGES_DOMAIN = "show-images-domain";


    // Widget used to display sender/recipient email addresses in
    // message header Gtk.FlowBox instances.
    private class ContactFlowBoxChild : Gtk.FlowBoxChild {


        private const string PRIMARY_CLASS = "geary-primary";


        public enum Type { FROM, OTHER; }


        public Type address_type { get; private set; }

        public Application.Contact contact { get; private set; }

        public Geary.RFC822.MailboxAddress displayed { get; private set; }
        public Geary.RFC822.MailboxAddress source { get; private set; }

        private string search_value;

        private Gtk.Bin container;


        public ContactFlowBoxChild(Application.Contact contact,
                                   Geary.RFC822.MailboxAddress source,
                                   Type address_type = Type.OTHER) {
            this.contact = contact;
            this.source = source;
            this.address_type = address_type;
            this.search_value = source.to_searchable_string().casefold();

            // Update prelight state when mouse-overed.
            Gtk.EventBox events = new Gtk.EventBox();
            events.add_events(
                Gdk.EventMask.ENTER_NOTIFY_MASK |
                Gdk.EventMask.LEAVE_NOTIFY_MASK
            );
            events.set_visible_window(false);
            events.enter_notify_event.connect(on_prelight_in_event);
            events.leave_notify_event.connect(on_prelight_out_event);

            add(events);
            this.container = events;
            set_halign(Gtk.Align.START);

            this.contact.changed.connect(on_contact_changed);
            update();
        }

        public override void destroy() {
            this.contact.changed.disconnect(on_contact_changed);
            base.destroy();
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

        private void update() {
            // We use two GTK.Label instances here when address has
            // distinct parts so we can dim the secondary part, if
            // any. Ideally, it would be just one label instance in
            // both cases, but we can't yet include CSS classes in
            // Pango markup. See Bug 766763.

            Gtk.Grid address_parts = new Gtk.Grid();

            bool is_spoofed = this.source.is_spoofed();
            if (is_spoofed) {
                Gtk.Image spoof_img = new Gtk.Image.from_icon_name(
                    "dialog-warning-symbolic", Gtk.IconSize.SMALL_TOOLBAR
                );
                this.set_tooltip_text(
                    _("This email address may have been forged")
                );
                address_parts.add(spoof_img);
                get_style_context().add_class(SPOOF_CLASS);
            }

            Gtk.Label primary = new Gtk.Label(null);
            primary.ellipsize = Pango.EllipsizeMode.END;
            primary.set_halign(Gtk.Align.START);
            primary.get_style_context().add_class(PRIMARY_CLASS);
            if (this.address_type == Type.FROM) {
                primary.get_style_context().add_class(FROM_CLASS);
            }
            address_parts.add(primary);

            string display_address = this.source.to_address_display("", "");

            if (is_spoofed || this.contact.display_name_is_email) {
                // Don't display the name to avoid duplication and/or
                // reduce the chance of the user of being tricked by
                // malware.
                primary.set_text(display_address);
                // Use the source as the displayed address so that the
                // contact popover uses the spoofed mailbox and
                // displays it as being spoofed.
                this.displayed = this.source;
            } else if (this.contact.is_trusted) {
                // The contact's name can be trusted, so no need to
                // display the email address
                primary.set_text(this.contact.display_name);
                this.displayed = new Geary.RFC822.MailboxAddress(
                    this.contact.display_name, this.source.address
                );
                this.tooltip_text = this.source.address;
            } else {
                // Display both the display name and the email address
                // so that the user has the full information at hand
                primary.set_text(this.contact.display_name);
                this.displayed = new Geary.RFC822.MailboxAddress(
                    this.contact.display_name, this.source.address
                );

                Gtk.Label secondary = new Gtk.Label(null);
                secondary.ellipsize = Pango.EllipsizeMode.END;
                secondary.set_halign(Gtk.Align.START);
                secondary.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
                secondary.set_text(display_address);
                address_parts.add(secondary);
            }

            Gtk.Widget? existing_ui = this.container.get_child();
            if (existing_ui != null) {
                this.container.remove(existing_ui);
            }

            this.container.add(address_parts);
            show_all();
        }

        private void on_contact_changed() {
            update();
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

    /**
     * A FlowBox that limits its contents to 12 items until a link is
     * clicked to expand it. Used for to, cc, and bcc fields.
     */
    public class ContactList : Gtk.FlowBox, Geary.BaseInterface {
        /**
         * The number of results that will be displayed when not expanded.
         * Note this is actually one less than the cutoff, which is 12; we
         * don't want the show more label to be visible when we could just
         * put the last item.
         */
        private const int SHORT_RESULTS = 11;


        private Gtk.Label show_more;
        private Gtk.Label show_less;
        private bool expanded = false;
        private int children = 0;


        construct {
            this.show_more = this.create_label();
            this.show_more.activate_link.connect(() => {
                this.set_expanded(true);
            });
            base.add(this.show_more);

            this.show_less = this.create_label();
            // Translators: Label text displayed when there are too
            // many email addresses to be shown by default in an
            // email's header, but they are all being shown anyway.
            this.show_less.label = "<a href=''>%s</a>".printf(_("Show less"));
            this.show_less.activate_link.connect(() => {
                this.set_expanded(false);
            });
            base.add(this.show_less);

            this.set_filter_func(this.filter_func);
        }


        public override void add(Gtk.Widget child) {
            // insert before the show_more and show_less labels
            int length = (int) this.get_children().length();
            base.insert(child, length - 2);

            this.children ++;

            if (this.children >= SHORT_RESULTS && this.children <= SHORT_RESULTS + 2) {
                this.invalidate_filter();
            }

            this.show_more.label = "<a href=''>%s</a>".printf(
                // Translators: Label text displayed when there are
                // too many email addresses to be shown by default in
                // an email's header. The string substitution is the
                // number of extra email to be shown.
                ngettext("%d more…", "%d more…", this.children - SHORT_RESULTS).printf(this.children - SHORT_RESULTS)
            );
        }


        private Gtk.Label create_label() {
            var label = new Gtk.Label("");
            label.visible = true;
            label.use_markup = true;
            label.track_visited_links = false;
            label.halign = START;
            return label;
        }

        private void set_expanded(bool expanded) {
            this.expanded = expanded;
            this.invalidate_filter();
        }

        private bool filter_func(Gtk.FlowBoxChild child) {
            bool is_expandable = this.children > SHORT_RESULTS + 1;

            if (child.get_child() == this.show_more) {
                return !this.expanded && is_expandable;
            } else if (child.get_child() == this.show_less) {
                return this.expanded;
            } else if (!this.expanded && is_expandable) {
                return child.get_index() < SHORT_RESULTS;
            } else {
                return true;
            }
        }
    }


    /** Contact for the primary originator, if any. */
    internal Application.Contact? primary_contact {
        get; private set;
    }

    /** Mailbox assumed to be the primary sender. */
    internal Geary.RFC822.MailboxAddress? primary_originator {
        get; private set;
    }

    /** Container for preview and full header widgets.  */
    [GtkChild] internal unowned Gtk.Grid summary { get; }

    /** Container for message body components.  */
    [GtkChild] internal unowned Gtk.Grid body_container { get; }

    /** Conainer for message InfoBar widgets. */
    [GtkChild] internal unowned Components.InfoBarStack info_bars  { get; }

    /**
     * Emitted when web_view's content has finished loaded.
     *
     * See {@link Components.WebView.is_content_loaded} for details.
     */
    internal bool is_content_loaded {
        get {
            return this.web_view != null && this.web_view.is_content_loaded;
        }
    }

    /** HTML view that displays the message body. */
    private ConversationWebView? web_view { get; private set; }

    // The message headers represented by this view
    private Geary.EmailHeaderSet headers;

    private Application.Configuration config;

    // Store from which to lookup contacts
    private Application.ContactStore contacts;

    private GLib.DateTime? local_date = null;

    [GtkChild] private unowned Hdy.Avatar avatar;

    [GtkChild] private unowned Gtk.Revealer compact_revealer;
    [GtkChild] private unowned Gtk.Label compact_from;
    [GtkChild] private unowned Gtk.Label compact_date;
    [GtkChild] private unowned Gtk.Label compact_body;

    [GtkChild] private unowned Gtk.Revealer header_revealer;
    [GtkChild] private unowned Gtk.FlowBox from;
    [GtkChild] private unowned Gtk.Label subject;
    private string subject_searchable = "";
    [GtkChild] private unowned Gtk.Label date;

    [GtkChild] private unowned Gtk.Grid sender_header;
    [GtkChild] private unowned Gtk.FlowBox sender_address;

    [GtkChild] private unowned Gtk.Grid reply_to_header;
    [GtkChild] private unowned Gtk.FlowBox reply_to_addresses;

    [GtkChild] private unowned Gtk.Grid to_header;
    [GtkChild] private unowned Gtk.Grid cc_header;
    [GtkChild] private unowned Gtk.Grid bcc_header;

    [GtkChild] private unowned Gtk.Revealer body_revealer;
    [GtkChild] private unowned Gtk.ProgressBar body_progress;

    private Components.InfoBar? remote_images_info_bar = null;

    private Gtk.Widget? body_placeholder = null;

    private string empty_from_label;

    // The web_view's context menu
    private Gtk.Menu? context_menu = null;

    // Menu models for creating the context menu
    private MenuModel context_menu_link;
    private MenuModel context_menu_email;
    private MenuModel context_menu_image;
    private MenuModel context_menu_main;
    private MenuModel? context_menu_inspector = null;

    // Menu model for creating the show images menu
    private MenuModel show_images_menu;

    // Address fields that can be search through
    private Gee.List<ContactFlowBoxChild> searchable_addresses =
        new Gee.LinkedList<ContactFlowBoxChild>();

    // Resource that have been loaded by the web view
    private Gee.Map<string,WebKit.WebResource> resources =
        new Gee.HashMap<string,WebKit.WebResource>();

    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    private int next_replaced_buffer_number = 0;

    // Is the view set to allow remote image loads?
    private bool load_remote_resources;

    private int remote_resources_requested = 0;

    private int remote_resources_loaded = 0;

    private bool authenticated_message = false;

    // Timeouts for showing the progress bar and hiding it when
    // complete. The former is so that when loading cached images it
    // doesn't pop up and then go away immediately afterwards.
    private Geary.TimeoutManager show_progress_timeout = null;
    private Geary.TimeoutManager hide_progress_timeout = null;

    // Timer for pulsing progress bar
    private Geary.TimeoutManager progress_pulse;


    /** Fired when the user clicks a internal link in the email. */
    public signal void internal_link_activated(int y);

    /** Fired when the email should be flagged for remote image loading. */
    public signal void flag_remote_images();

    /** Fired when the user saves an inline displayed image. */
    public signal void save_image(
        string uri, string? alt_text, Geary.Memory.Buffer? buffer
    );

    /** Emitted when web_view has loaded a resource added to it. */
    public signal void internal_resource_loaded(string name);

    /** Emitted when web_view's selection has changed. */
    public signal void selection_changed(bool has_selection);

    /**
     * Emitted when web_view's content has finished loaded.
     *
     * See {@link Components.WebView.is_content_loaded} for details.
     */
    public signal void content_loaded();


    /**
     * Constructs a new view from an email's headers and body.
     *
     * This method sets up most of the user interface for displaying
     * the message, but does not attempt any possibly long-running
     * loading processes.
     */
    public ConversationMessage.from_email(Geary.Email email,
                                          bool load_remote_resources,
                                          Application.ContactStore contacts,
                                          Application.Configuration config) {
        this(
            email,
            email.preview != null ? email.preview.buffer.get_valid_utf8() : null,
            load_remote_resources,
            contacts,
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
                                            bool load_remote_resources,
                                            Application.ContactStore contacts,
                                            Application.Configuration config) {
        this(
            message,
            message.get_preview(),
            load_remote_resources,
            contacts,
            config
        );
    }

    private void trigger_internal_resource_loaded(string name) {
        internal_resource_loaded(name);
    }

    private void trigger_content_loaded() {
        content_loaded();
    }

    private ConversationMessage(Geary.EmailHeaderSet headers,
                                string? preview,
                                bool load_remote_resources,
                                Application.ContactStore contacts,
                                Application.Configuration config) {
        base_ref();
        this.headers = headers;
        this.load_remote_resources = load_remote_resources;
        this.primary_originator = Util.Email.get_primary_originator(headers);
        this.config = config;
        this.contacts = contacts;

        // Actions

        add_action(ACTION_CONVERSATION_NEW, true, VariantType.STRING)
            .activate.connect(on_link_activated);
        add_action(ACTION_COPY_EMAIL, true, VariantType.STRING)
            .activate.connect(on_copy_email_address);
        add_action(ACTION_COPY_LINK, true, VariantType.STRING)
            .activate.connect(on_copy_link);
        add_action(ACTION_OPEN_LINK, true, VariantType.STRING)
            .activate.connect(on_link_activated);
        add_action(ACTION_SAVE_IMAGE, true, new VariantType("(sms)"))
            .activate.connect(on_save_image);
        add_action(ACTION_SHOW_IMAGES_MESSAGE, true)
            .activate.connect(on_show_images);
        add_action(ACTION_SHOW_IMAGES_SENDER, true)
            .activate.connect(on_show_images_sender);
        add_action(ACTION_SHOW_IMAGES_DOMAIN, true)
            .activate.connect(on_show_images_domain);
        insert_action_group("msg", message_actions);

        // Context menu

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menus.ui"
        );
        context_menu_link = (MenuModel) builder.get_object("context_menu_link");
        context_menu_email = (MenuModel) builder.get_object("context_menu_email");
        context_menu_image = (MenuModel) builder.get_object("context_menu_image");
        context_menu_main = (MenuModel) builder.get_object("context_menu_main");

        show_images_menu = (MenuModel) builder.get_object("show_images_menu");

        if (config.enable_inspector) {
            context_menu_inspector =
                (MenuModel) builder.get_object("context_menu_inspector");
        }

        if (headers.date != null) {
            this.local_date = headers.date.value.to_local();
        }
        update_display();

        // Compact headers. These are partially done here and partially
        // in load_contacts.

        // Translators: This is displayed in place of the from address
        // when the message has no from address.
        this.empty_from_label = _("No sender");

        this.compact_from.get_style_context().add_class(FROM_CLASS);

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

        // Full headers. These are partially done here and partially
        // in load_contacts.

        if (headers.subject != null) {
            this.subject.set_text(headers.subject.value);
            this.subject.set_visible(true);
            this.subject_searchable = headers.subject.value.casefold();
        }

        this.body_container.set_has_tooltip(true); // Used to show link URLs
        this.show_progress_timeout = new Geary.TimeoutManager.milliseconds(
            Util.Gtk.SHOW_PROGRESS_TIMEOUT_MSEC, this.on_show_progress_timeout
        );
        this.hide_progress_timeout = new Geary.TimeoutManager.milliseconds(
            Util.Gtk.HIDE_PROGRESS_TIMEOUT_MSEC, this.on_hide_progress_timeout
        );

        this.progress_pulse = new Geary.TimeoutManager.milliseconds(
            Util.Gtk.PROGRESS_PULSE_TIMEOUT_MSEC, this.body_progress.pulse
        );
        this.progress_pulse.repetition = FOREVER;
    }

    private void initialize_web_view() {
        var viewer = get_ancestor(typeof(ConversationViewer)) as ConversationViewer;

        // Ensure we share the same WebProcess with the last one
        // constructed if possible.
        if (viewer != null && viewer.previous_web_view != null) {
            this.web_view = new ConversationWebView.with_related_view(
                this.config,
                viewer.previous_web_view
            );
        } else {
            this.web_view = new ConversationWebView(this.config);
        }
        if (viewer != null) {
            viewer.previous_web_view = this.web_view;
        }

        this.web_view.context_menu.connect(on_context_menu);
        this.web_view.deceptive_link_clicked.connect(on_deceptive_link_clicked);
        this.web_view.link_activated.connect((link) => {
                on_link_activated(new GLib.Variant("s", link));
            });
        this.web_view.mouse_target_changed.connect(on_mouse_target_changed);
        this.web_view.notify["has-selection"].connect(on_selection_changed);
        this.web_view.resource_load_started.connect(on_resource_load_started);
        this.web_view.remote_resource_load_blocked.connect(on_remote_resources_blocked);
        this.web_view.internal_resource_loaded.connect(trigger_internal_resource_loaded);
        this.web_view.content_loaded.connect(trigger_content_loaded);
        this.web_view.set_hexpand(true);
        this.web_view.set_vexpand(true);
        this.web_view.show();
        this.body_container.add(this.web_view);
        add_action(ACTION_COPY_SELECTION, false).activate.connect(() => {
                web_view.copy_clipboard();
            });
        add_action(ACTION_OPEN_INSPECTOR, config.enable_inspector).activate.connect(() => {
                this.web_view.get_inspector().show();
            });
        add_action(ACTION_SELECT_ALL, true).activate.connect(() => {
                web_view.select_all();
            });
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

    public async string? get_selection_for_quoting() throws Error {
        if (this.web_view == null)
            initialize_web_view();
        return yield web_view.get_selection_for_quoting();
    }

    public async string? get_selection_for_find() throws Error {
        if (this.web_view == null)
            initialize_web_view();
        return yield web_view.get_selection_for_find();
    }

    /**
     * Adds a set of internal resources to web_view.
     *
     * @see Components.WebView.add_internal_resources
     */
    public void add_internal_resources(Gee.Map<string,Geary.Memory.Buffer> res) {
        if (this.web_view == null)
            initialize_web_view();
        web_view.add_internal_resources(res);
    }

    public WebKit.PrintOperation new_print_operation() {
        if (this.web_view == null)
            initialize_web_view();
        return new WebKit.PrintOperation(web_view);
    }

    public async void evaluate_javascript(string script, Cancellable? cancellable) throws Error {
        if (this.web_view == null)
            initialize_web_view();
        yield web_view.evaluate_javascript(script, -1, null, null, cancellable);
    }

    public void zoom_in() {
        if (this.web_view == null)
            initialize_web_view();
        web_view.zoom_in();
    }

    public void zoom_out() {
        if (this.web_view == null)
            initialize_web_view();
        web_view.zoom_out();
    }

    public void zoom_reset() {
        if (this.web_view == null)
            initialize_web_view();
        web_view.zoom_reset();
    }

    public void web_view_translate_coordinates(Gtk.Widget widget, int x, int anchor_y, out int x1, out int y1) {
        if (this.web_view == null)
            initialize_web_view();
        web_view.translate_coordinates(widget, x, anchor_y, out x1, out y1);
    }

    public int web_view_get_allocated_height() {
        if (this.web_view == null)
            initialize_web_view();
        return web_view.get_allocated_height();
    }

    /**
     * Shows the complete message and hides the compact headers.
     */
    public void show_message_body(bool include_transitions=true) {
        if (this.web_view == null)
            initialize_web_view();
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
    public void start_progress_loading() {
        this.progress_pulse.reset();
        this.body_progress.fraction = 0.1;
        this.show_progress_timeout.start();
        this.hide_progress_timeout.reset();
    }

    /** Hides the progress meter. */
    public void stop_progress_loading() {
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
     * Starts loading message contacts and the avatar.
     */
    public async void load_contacts(GLib.Cancellable cancellable)
        throws GLib.Error {
        var main = this.get_toplevel() as Application.MainWindow;
        if (main != null && !cancellable.is_cancelled()) {
            // Load the primary contact and avatar
            if (this.primary_originator != null) {
                this.primary_contact = yield this.contacts.load(
                    this.primary_originator, cancellable
                );

                if (this.primary_contact != null) {
                    this.primary_contact.bind_property("display-name",
                                                       this.avatar,
                                                       "text",
                                                       BindingFlags.SYNC_CREATE);
                    this.primary_contact.bind_property("avatar",
                                                       this.avatar,
                                                       "loadable-icon",
                                                       BindingFlags.SYNC_CREATE);
                }
            }

            // Preview headers
            this.compact_from.set_text(
                yield format_originator_compact(cancellable)
            );

            // Full headers
            Geary.EmailHeaderSet headers = this.headers;
            yield fill_originator_addresses(
                headers.from,
                headers.reply_to,
                headers.sender,
                cancellable
            );
            yield fill_header_addresses(
                this.to_header, headers.to, cancellable
            );
            yield fill_header_addresses(
                this.cc_header, headers.cc, cancellable
            );
            yield fill_header_addresses(
                this.bcc_header, headers.bcc, cancellable
            );
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

        if (this.web_view == null) {
            initialize_web_view();
        }

        bool contact_load_images = Util.Contact.should_load_images(
            this.primary_contact, this.config
        );
        this.authenticated_message = message.auth_results != null && (
            message.auth_results.is_dkim_valid() ||
            message.auth_results.is_dmarc_valid()
        );
        if (this.load_remote_resources || (
                contact_load_images && this.authenticated_message)) {
            yield this.web_view.load_remote_resources(load_cancelled);
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
     * message body. returns the number of matching search terms.
     */
    public async uint highlight_search_terms(Gee.Set<string> search_matches,
                                             GLib.Cancellable cancellable)
        throws GLib.IOError.CANCELLED {
        uint headers_found = 0;
        foreach(string raw_match in search_matches) {
            string match = raw_match.casefold();

            if (this.subject_searchable.contains(match)) {
                this.subject.get_style_context().add_class(MATCH_CLASS);
                ++headers_found;
            } else {
                this.subject.get_style_context().remove_class(MATCH_CLASS);
            }

            foreach (ContactFlowBoxChild address in this.searchable_addresses) {
                if (address.highlight_search_term(match)) {
                    ++headers_found;
                }
            }
        }

        if (this.web_view == null)
            initialize_web_view();
        uint webkit_found = yield this.web_view.highlight_search_terms(
            search_matches, cancellable
        );
        return headers_found + webkit_found;
    }

    /**
     * Disables highlighting of any search terms in the message view.
     */
    public void unmark_search_terms() {
        foreach (ContactFlowBoxChild address in this.searchable_addresses) {
            address.unmark_search_terms();
        }

        if (this.web_view != null)
            this.web_view.unmark_search_terms();
    }

    /**
     * Updates the displayed date for each conversation row.
     */
    public void update_display() {
        string date_text = "";
        string date_tooltip = "";
        if (this.local_date != null) {
            date_text = Util.Date.pretty_print(
                this.local_date, this.config.clock_format
            );
            date_tooltip = Util.Date.pretty_print_verbose(
                this.local_date, this.config.clock_format
            );
        }

        this.compact_date.set_text(date_text);
        this.compact_date.set_tooltip_text(date_tooltip);

        this.date.set_text(date_text);
        this.date.set_tooltip_text(date_tooltip);
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

    private async string format_originator_compact(GLib.Cancellable cancellable)
        throws GLib.Error {
        Geary.RFC822.MailboxAddresses? from = this.headers.from;
        string text = "";
        if (from != null && from.size > 0) {
            int i = 0;
            Gee.List<Geary.RFC822.MailboxAddress> list = from.get_all();
            foreach (Geary.RFC822.MailboxAddress addr in list) {
                Application.Contact originator = yield this.contacts.load(
                    addr, cancellable
                );
                text += originator.display_name;

                if (++i < list.size)
                    // Translators: This separates multiple 'from'
                    // addresses in the compact header for a message.
                    text += _(", ");
            }
        } else {
            text = this.empty_from_label;
        }

        return text;
    }

    private async void fill_originator_addresses(Geary.RFC822.MailboxAddresses? from,
                                                 Geary.RFC822.MailboxAddresses? reply_to,
                                                 Geary.RFC822.MailboxAddress? sender,
                                                 GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Show any From header addresses
        if (from != null && from.size > 0) {
            foreach (Geary.RFC822.MailboxAddress address in from) {
                ContactFlowBoxChild child = new ContactFlowBoxChild(
                    yield this.contacts.load(address, cancellable),
                    address,
                    ContactFlowBoxChild.Type.FROM
                );
                this.searchable_addresses.add(child);
                this.from.add(child);
            }
        } else {
            Gtk.Label label = new Gtk.Label(null);
            label.set_text(this.empty_from_label);

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
            ContactFlowBoxChild child = new ContactFlowBoxChild(
                yield this.contacts.load(sender, cancellable),
                sender
            );
            this.searchable_addresses.add(child);
            this.sender_header.show();
            this.sender_address.add(child);
        }

        // Show any Reply-To header addresses if present, but only if
        // each is not already in the From header.
        if (reply_to != null) {
            foreach (Geary.RFC822.MailboxAddress address in reply_to) {
                if (from == null || !from.contains_normalized(address.address)) {
                    ContactFlowBoxChild child = new ContactFlowBoxChild(
                        yield this.contacts.load(address, cancellable),
                        address
                    );
                    this.searchable_addresses.add(child);
                    this.reply_to_addresses.add(child);
                    this.reply_to_header.show();
                }
            }
        }
    }

    private async void fill_header_addresses(Gtk.Grid header,
                                             Geary.RFC822.MailboxAddresses? addresses,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (addresses != null && addresses.size > 0) {
            ContactList box = header.get_children().nth(0).data as ContactList;
            if (box != null) {
                foreach (Geary.RFC822.MailboxAddress address in addresses) {
                    ContactFlowBoxChild child = new ContactFlowBoxChild(
                        yield this.contacts.load(address, cancellable),
                        address
                    );
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
        if (this.web_view == null)
            initialize_web_view();
        Geary.Mime.ContentType content_type = part.content_type;
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
            this.web_view.add_internal_resource(
                id,
                part.write_to_buffer(Geary.RFC822.Part.EncodingConversion.UTF8)
            );
        } catch (Geary.RFC822.Error err) {
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
            Components.WebView.CID_URL_PREFIX,
            Geary.HTML.escape_markup(id)
        );
    }

    private void show_images(bool update_email_flag) {
        if (this.remote_images_info_bar != null) {
            this.info_bars.remove(this.remote_images_info_bar);
            this.remote_images_info_bar = null;
        }
        this.load_remote_resources = true;
        this.remote_resources_requested = 0;
        this.remote_resources_loaded = 0;
        if (this.web_view != null) {
            this.web_view.load_remote_resources.begin(null);
        }
        if (update_email_flag) {
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
            if (this.web_view != null)
                this.web_view.hide();
            this.body_container.add(placeholder);
            show_message_body(true);
        } else {
            if (this.web_view != null)
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

    private void on_resource_load_started(WebKit.WebView view,
                                          WebKit.WebResource res,
                                          WebKit.URIRequest req) {
        // Cache the resource to allow images to be saved
        this.resources[res.get_uri()] = res;

        // Kick off the progress timer if this is the first or next in
        // a batch
        if (this.remote_resources_loaded == this.remote_resources_requested) {
            start_progress_loading();
        }

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
        ContactFlowBoxChild address_child = child as ContactFlowBoxChild;
        if (address_child != null) {
            address_child.set_state_flags(Gtk.StateFlags.ACTIVE, false);

            Geary.RFC822.MailboxAddress address = address_child.displayed;

            Gee.Map<string,GLib.Variant> values =
                new Gee.HashMap<string,GLib.Variant>();
            values[ACTION_COPY_EMAIL] = address.to_full_display();

            Conversation.ContactPopover popover = new Conversation.ContactPopover(
                address_child,
                address_child.contact,
                address,
                this.config
            );
            popover.set_position(Gtk.PositionType.BOTTOM);
            popover.load_remote_resources_changed.connect((enabled) => {
                    if (this.primary_contact.equal_to(address_child.contact) &&
                        enabled) {
                        show_images(false);
                    }
                });
            popover.closed.connect(() => {
                    address_child.unset_state_flags(Gtk.StateFlags.ACTIVE);
                });
            popover.popup();
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
                link_url.has_prefix(MAILTO_URI_PREFIX)
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
            hit_test.context_is_link()
            ? Util.Gtk.shorten_url(hit_test.get_link_uri())
            : null
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
        if (GLib.Uri.parse_scheme(text_href) == null) {
            text_href = "http://" + text_href;
        }
        string? text_label = GLib.Uri.unescape_string(text_href) ?? _("(unknown)");

        string anchor_href = href;
        if (GLib.Uri.parse_scheme(anchor_href) == null) {
            anchor_href = "http://" + anchor_href;
        }
        string anchor_label = GLib.Uri.unescape_string(anchor_href) ?? _("(unknown)");

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-link-popover.ui"
        );
        var link_popover = builder.get_object("link_popover") as Gtk.Popover;
        var good_link = builder.get_object("good_link_label") as Gtk.Label;
        var bad_link = builder.get_object("bad_link_label") as Gtk.Label;

        // Escape text and especially URLs since we got them from the
        // HREF, and Gtk.Label.set_markup is a strict parser.

        var main = get_toplevel() as Application.MainWindow;

        good_link.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", text_href, text_label)
        );
        good_link.activate_link.connect((label, uri) => {
                link_popover.popdown();
                main.application.show_uri.begin(uri);
                return Gdk.EVENT_STOP;
            }
        );

        bad_link.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", anchor_href, anchor_label)
        );
        bad_link.activate_link.connect((label, uri) => {
                link_popover.popdown();
                main.application.show_uri.begin(uri);
                return Gdk.EVENT_STOP;
            }
        );

        link_popover.set_relative_to(this.web_view);
        link_popover.set_pointing_to(location);
        link_popover.closed.connect_after(() => { link_popover.destroy(); });
        link_popover.popup();
    }

    private void on_selection_changed() {
        set_action_enabled(ACTION_COPY_SELECTION, this.web_view.has_selection);
        selection_changed(this.web_view.has_selection);
    }

    private void on_remote_resources_blocked() {
        if (this.remote_images_info_bar == null) {
            /* If message is authenticated, user is allowed to whitelist
             * images loading for sender/domain sender.
             */
            if (this.authenticated_message) {
                this.remote_images_info_bar = new Components.InfoBar(
                    // Translators: Info bar status message
                    _("Remote images not shown"),
                    // Translators: Info bar description
                    _("Showing remote images allows the sender to track you")
                );

                var menu_image = new Gtk.Image();
                menu_image.icon_name = "view-more-symbolic";

                var menu_button = new Gtk.MenuButton();
                menu_button.use_popover = true;
                menu_button.image = menu_image;
                menu_button.menu_model = this.show_images_menu;
                menu_button.halign = Gtk.Align.END;
                menu_button.hexpand =true;
                menu_button.show_all();

                this.remote_images_info_bar.get_action_area().add(menu_button);
            } else {
                this.remote_images_info_bar = new Components.InfoBar(
                    // Translators: Info bar status message
                    _("Remote images not shown"),
                    // Translators: Info bar description
                    _("This message can't be trusted.")
                );
                this.remote_images_info_bar.add_button(
                    // Translators: Info bar button label
                    _("Show"), 1
                );
                this.remote_images_info_bar.response.connect(() => {
                    show_images(true);
                });
            }
            this.info_bars.add(this.remote_images_info_bar);
        }
    }

    private void on_copy_link(Variant? param) {
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(param.get_string(), -1);
        clipboard.store();
    }

    private void on_copy_email_address(Variant? param) {
        string value = param.get_string();
        if (value.has_prefix(MAILTO_URI_PREFIX)) {
            value = value.substring(MAILTO_URI_PREFIX.length, -1);
        }
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(value, -1);
        clipboard.store();
    }

    private void on_save_image(Variant? param) {
        string uri = (string) param.get_child_value(0);
        string? alt_text = null;
        Variant? alt_maybe = param.get_child_value(1).get_maybe();
        if (alt_maybe != null) {
            alt_text = (string) alt_maybe;
        }

        if (uri.has_prefix(Components.WebView.CID_URL_PREFIX)) {
            // We can get the data directly from the attachment, so
            // don't bother getting it from the web view
            save_image(uri, alt_text, null);
        } else {
            WebKit.WebResource response = this.resources.get(uri);
            response.get_data.begin(null, (obj, res) => {
                    try {
                        uint8[] data = response.get_data.end(res);
                        save_image(
                            uri,
                            alt_text,
                            new Geary.Memory.ByteBuffer(data, data.length)
                        );
                    } catch (GLib.Error err) {
                        debug(
                            "Failed to get image data from web view: %s",
                            err.message
                        );
                    }
                });
        }
    }

    private void on_show_images(Variant? param) {
        show_images(true);
    }

    private void on_show_images_sender(Variant? param) {
        show_images(false);
        if (this.primary_contact != null) {
            this.primary_contact.set_remote_resource_loading.begin(
                true, null
            );
        }
    }

    private void on_show_images_domain(Variant? param) {
        show_images(false);
        if (this.primary_contact != null) {
            var email_addresses = this.primary_contact.email_addresses;
            foreach (Geary.RFC822.MailboxAddress email in email_addresses) {
                this.config.add_images_trusted_domain(email.domain);
                break;
            }
        }
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
            var main = this.get_toplevel() as Application.MainWindow;
            if (main != null) {
                main.application.show_uri.begin(link);
            }
        }
    }

}
