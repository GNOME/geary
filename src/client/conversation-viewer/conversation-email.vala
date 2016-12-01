/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an email in a conversation.
 *
 * This view corresponds to {@link Geary.Email}, displaying the
 * email's primary message (a {@link Geary.RFC822.Message}), any
 * sub-messages (also instances of {@link Geary.RFC822.Message}) and
 * attachments. The RFC822 messages are themselves displayed by {@link
 * ConversationMessage}.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-email.ui")]
public class ConversationEmail : Gtk.Box {
    // This isn't a Gtk.Grid since when added to a Gtk.ListBoxRow the
    // hover style isn't applied to it.


    /**
     * Iterator that returns all message views in an email view.
     */
    private class MessageViewIterator :
        Gee.Traversable<ConversationMessage>, Gee.Iterator<ConversationMessage>, Object {

        public bool read_only {
            get { return true; }
        }
        public bool valid {
            get { return this.pos == 0 || this.attached_views.valid; }
        }

        private ConversationEmail parent_view;
        private int pos = -1;
        private Gee.Iterator<ConversationMessage>? attached_views = null;

        internal MessageViewIterator(ConversationEmail parent_view) {
            this.parent_view = parent_view;
            this.attached_views = parent_view._attached_messages.iterator();
        }

        public bool next() {
            if (!has_next()) {
                return false;
            }
            if (this.pos == -1) {
                this.pos = 0;
            } else {
                this.attached_views.next();
            }
            return true;
        }

        public bool has_next() {
            return this.pos == -1 || this.attached_views.next();
        }

        public new ConversationMessage get() {
            switch (this.pos) {
            case -1:
                assert_not_reached();

            case 0:
                this.pos = 1;
                return this.parent_view.primary_message;

            default:
                return this.attached_views.get();
            }
        }

        public void remove() {
            assert_not_reached();
        }

        public new bool foreach(Gee.ForallFunc<ConversationMessage> f) {
            this.pos = 1;
            bool ret = f(this.parent_view.primary_message);
            if (ret) {
                ret = this.attached_views.foreach(f);
            }
            return ret;
        }

    }


    // Displays an attachment's icon and details
    [GtkTemplate (ui = "/org/gnome/Geary/conversation-email-attachment-view.ui")]
    private class AttachmentView : Gtk.Grid {

        public Geary.Attachment attachment { get; private set; }

        [GtkChild]
        private Gtk.Image icon;

        [GtkChild]
        private Gtk.Label filename;

        [GtkChild]
        private Gtk.Label description;

        private string gio_content_type;

        public AttachmentView(Geary.Attachment attachment) {
            this.attachment = attachment;
            string mime_content_type = attachment.content_type.get_mime_type();
            this.gio_content_type = ContentType.from_mime_type(
                mime_content_type
            );

            string file_name = null;
            if (attachment.has_supplied_filename) {
                file_name = attachment.file.get_basename();
            }
            string file_desc = ContentType.get_description(gio_content_type);
            if (ContentType.is_unknown(gio_content_type)) {
                // Translators: This is the file type displayed for
                // attachments with unknown file types.
                file_desc = _("Unknown");
            }
            string file_size = Files.get_filesize_as_string(attachment.filesize);

            // XXX Geary.ImapDb.Attachment will use "none" when
            // saving attachments with no filename to disk, this
            // seems to be getting saved to be the filename and
            // passed back, breaking the has_supplied_filename
            // test - so check for it here.
            if (file_name == null ||
                file_name == "" ||
                file_name == "none") {
                // XXX Check for unknown types here and try to guess
                // using attachment data.
                file_name = file_desc;
                file_desc = file_size;
            } else {
                // Translators: The first argument will be a
                // description of the document type, the second will
                // be a human-friendly size string. For example:
                // Document (100.9MB)
                file_desc = _("%s (%s)".printf(file_desc, file_size));
            }
            this.filename.set_text(file_name);
            this.description.set_text(file_desc);
        }

        internal async void load_icon(Cancellable load_cancelled) {
            if (load_cancelled.is_cancelled()) {
                return;
            }

            Gdk.Pixbuf? pixbuf = null;

            // XXX We need to hook up to GtkWidget::style-set and
            // reload the icon when the theme changes.

            int window_scale = get_scale_factor();
            try {
                // If the file is an image, use it. Otherwise get the
                // icon for this mime_type.
                if (this.attachment.content_type.has_media_type("image")) {
                    // Get a thumbnail for the image.
                    // TODO Generate and save the thumbnail when
                    // extracting the attachments rather than when showing
                    // them in the viewer.
                    int preview_size = ATTACHMENT_PREVIEW_SIZE * window_scale;
                    InputStream stream = yield this.attachment.file.read_async(
                        Priority.DEFAULT,
                        load_cancelled
                    );
                    pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                        stream, preview_size, preview_size, true, load_cancelled
                    );
                    pixbuf = pixbuf.apply_embedded_orientation();
                } else {
                    // Load the icon for this mime type
                    Icon icon = ContentType.get_icon(this.gio_content_type);
                    Gtk.IconTheme theme = Gtk.IconTheme.get_default();
                    Gtk.IconLookupFlags flags = Gtk.IconLookupFlags.DIR_LTR;
                    if (get_direction() == Gtk.TextDirection.RTL) {
                        flags = Gtk.IconLookupFlags.DIR_RTL;
                    }
                    Gtk.IconInfo? icon_info = theme.lookup_by_gicon_for_scale(
                        icon, ATTACHMENT_ICON_SIZE, window_scale, flags
                    );
                    if (icon_info != null) {
                        pixbuf = yield icon_info.load_icon_async(load_cancelled);
                    }
                }
            } catch (Error error) {
                debug("Failed to load icon for attachment '%s': %s",
                      this.attachment.id,
                      error.message);
            }

            if (pixbuf != null) {
                Cairo.Surface surface = Gdk.cairo_surface_create_from_pixbuf(
                    pixbuf, window_scale, get_window()
                );
                this.icon.set_from_surface(surface);
            }
        }

    }


    private const int ATTACHMENT_ICON_SIZE = 32;
    private const int ATTACHMENT_PREVIEW_SIZE = 64;

    private const string ACTION_FORWARD = "forward";
    private const string ACTION_MARK_READ = "mark_read";
    private const string ACTION_MARK_UNREAD = "mark_unread";
    private const string ACTION_MARK_UNREAD_DOWN = "mark_unread_down";
    private const string ACTION_OPEN_ATTACHMENTS = "open_attachments";
    private const string ACTION_PRINT = "print";
    private const string ACTION_REPLY_SENDER = "reply_sender";
    private const string ACTION_REPLY_ALL = "reply_all";
    private const string ACTION_SAVE_ATTACHMENTS = "save_attachments";
    private const string ACTION_SAVE_ALL_ATTACHMENTS = "save_all_attachments";
    private const string ACTION_SELECT_ALL_ATTACHMENTS = "select_all_attachments";
    private const string ACTION_STAR = "star";
    private const string ACTION_UNSTAR = "unstar";
    private const string ACTION_VIEW_SOURCE = "view_source";

    private const string MANUAL_READ_CLASS = "geary-manual-read";
    private const string SENT_CLASS = "geary-sent";
    private const string STARRED_CLASS = "geary-starred";
    private const string UNREAD_CLASS = "geary-unread";

    /** The specific email that is displayed by this view. */
    public Geary.Email email { get; private set; }

    /** Determines if the email is showing a preview or the full message. */
    public bool is_collapsed = true;

    /** Determines if the email has been manually marked as being read. */
    public bool is_manually_read {
        get { return get_style_context().has_class(MANUAL_READ_CLASS); }
        set {
            if (value) {
                get_style_context().add_class(MANUAL_READ_CLASS);
            } else {
                get_style_context().remove_class(MANUAL_READ_CLASS);
            }
        }
    }

    /** The view displaying the email's primary message headers and body. */
    public ConversationMessage primary_message { get; private set; }

    /** Views for attached messages. */
    public Gee.List<ConversationMessage> attached_messages {
        owned get { return this._attached_messages.read_only_view; }
    }

    /** Determines if all message's web views have finished loading. */
    public bool message_bodies_loaded { get; private set; default = false; }

    // Backing for attached_messages
    private Gee.List<ConversationMessage> _attached_messages =
        new Gee.LinkedList<ConversationMessage>();

    // Contacts for the email's account
    private Geary.ContactStore contact_store;

    // Message view with selected text, if any
    private ConversationMessage? body_selection_message = null;

    // Attachment ids that have been displayed inline
    private Gee.HashSet<string> inlined_content_ids = new Gee.HashSet<string>();

    // A subset of the message's attachments that are displayed in the
    // attachments view
    Gee.Collection<Geary.Attachment> displayed_attachments =
         new Gee.LinkedList<Geary.Attachment>();

    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    [GtkChild]
    private Gtk.Grid actions;

    [GtkChild]
    private Gtk.Button attachments_button;

    [GtkChild]
    private Gtk.Button star_button;

    [GtkChild]
    private Gtk.Button unstar_button;

    [GtkChild]
    private Gtk.MenuButton email_menubutton;

    [GtkChild]
    private Gtk.InfoBar draft_infobar;

    [GtkChild]
    private Gtk.InfoBar not_saved_infobar;

    [GtkChild]
    private Gtk.Grid sub_messages;

    [GtkChild]
    private Gtk.Grid attachments;

    [GtkChild]
    private Gtk.FlowBox attachments_view;

    [GtkChild]
    private Gtk.Button select_all_attachments;

    private Gtk.Menu attachments_menu;


    /** Fired when the user clicks "reply" in the message menu. */
    public signal void reply_to_message();

    /** Fired when the user clicks "reply all" in the message menu. */
    public signal void reply_all_message();

    /** Fired when the user clicks "forward" in the message menu. */
    public signal void forward_message();

    /** Fired when the user updates the email's flags. */
    public signal void mark_email(
        Geary.NamedFlag? to_add, Geary.NamedFlag? to_remove
    );

    /** Fired when the user updates flags for this email and all others down. */
    public signal void mark_email_from_here(
        Geary.NamedFlag? to_add, Geary.NamedFlag? to_remove
    );

    /** Fired when the user activates an attachment. */
    public signal void attachments_activated(
        Gee.Collection<Geary.Attachment> attachments
    );

    /** Fired when the user saves an attachment. */
    public signal void save_attachments(
        Gee.Collection<Geary.Attachment> attachments
    );

    /** Fired the edit draft button is clicked. */
    public signal void edit_draft();

    /** Fired when the view source action is activated. */
    public signal void view_source();

    /** Fired when the user selects text in a message. */
    internal signal void body_selection_changed(bool has_selection);


    /**
     * Constructs a new view to display an email.
     *
     * This method sets up most of the user interface for displaying
     * the complete email, but does not attempt any possibly
     * long-running loading processes.
     */
    public ConversationEmail(Geary.Email email,
                             Geary.ContactStore contact_store,
                             bool is_sent,
                             bool is_draft) {
        this.email = email;
        this.contact_store = contact_store;

        if (is_sent) {
            get_style_context().add_class(SENT_CLASS);
        }

        add_action(ACTION_FORWARD).activate.connect(() => {
                forward_message();
            });
        add_action(ACTION_PRINT).activate.connect(() => {
                print();
            });
        add_action(ACTION_MARK_READ).activate.connect(() => {
                mark_email(null, Geary.EmailFlags.UNREAD);
            });
        add_action(ACTION_MARK_UNREAD).activate.connect(() => {
                mark_email(Geary.EmailFlags.UNREAD, null);
            });
        add_action(ACTION_MARK_UNREAD_DOWN).activate.connect(() => {
                mark_email_from_here(Geary.EmailFlags.UNREAD, null);
            });
        add_action(ACTION_OPEN_ATTACHMENTS, false).activate.connect(() => {
                attachments_activated(get_selected_attachments());
            });
        add_action(ACTION_REPLY_ALL).activate.connect(() => {
                reply_all_message();
            });
        add_action(ACTION_REPLY_SENDER).activate.connect(() => {
                reply_to_message();
            });
        add_action(ACTION_SAVE_ATTACHMENTS, false).activate.connect(() => {
                save_attachments(get_selected_attachments());
            });
        add_action(ACTION_SAVE_ALL_ATTACHMENTS).activate.connect(() => {
                save_attachments(this.displayed_attachments);
            });
        add_action(ACTION_SELECT_ALL_ATTACHMENTS, false).activate.connect(() => {
                this.attachments_view.select_all();
            });
        add_action(ACTION_STAR).activate.connect(() => {
                mark_email(Geary.EmailFlags.FLAGGED, null);
            });
        add_action(ACTION_UNSTAR).activate.connect(() => {
                mark_email(null, Geary.EmailFlags.FLAGGED);
            });
        add_action(ACTION_VIEW_SOURCE).activate.connect(() => {
                view_source();
            });
        insert_action_group("eml", message_actions);

        // Construct CID resources from attachments

        Gee.Map<string,Geary.Memory.Buffer> cid_resources =
            new Gee.HashMap<string,Geary.Memory.Buffer>();
        foreach (Geary.Attachment att in email.attachments) {
            if (att.content_id != null) {
                try {
                    cid_resources[att.content_id] =
                        new Geary.Memory.FileBuffer(att.file, true);
                } catch (Error err) {
                    debug("Could not open attachment: %s", err.message);
                }
            }
        }

        // Construct the view for the primary message, hook into it

        Geary.RFC822.Message message;
        try {
            message = email.get_message();
        } catch (Error error) {
            debug("Error loading primary message: %s", error.message);
            return;
        }

        bool load_images = email.load_remote_images().is_certain();
        Geary.Contact contact = this.contact_store.get_by_rfc822(
            message.get_primary_originator()
        );
        if (contact != null)  {
            load_images |= contact.always_load_remote_images();
        }

        this.primary_message = new ConversationMessage(message, load_images);
        this.primary_message.web_view.add_inline_resources(cid_resources);
        connect_message_view_signals(this.primary_message);

        this.primary_message.summary.add(this.actions);

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-email-menus.ui"
        );
        this.email_menubutton.set_menu_model(
            (MenuModel) builder.get_object("email_menu")
        );
        this.email_menubutton.set_sensitive(false);

        this.attachments_menu = new Gtk.Menu.from_model(
            (MenuModel) builder.get_object("attachments_menu")
        );
        this.attachments_menu.attach_to_widget(this, null);

        this.primary_message.infobars.add(this.draft_infobar);
        if (is_draft) {
            this.draft_infobar.show();
            this.draft_infobar.response.connect((infobar, response_id) => {
                    if (response_id == 1) { edit_draft(); }
                });
        }

        this.primary_message.infobars.add(this.not_saved_infobar);

        pack_start(this.primary_message, true, true, 0);
        update_email_state();

        // Add sub_messages container and message viewers if any

        Gee.List<Geary.RFC822.Message> sub_messages = message.get_sub_messages();
        if (sub_messages.size > 0) {
            this.primary_message.body.pack_start(
                this.sub_messages, false, false, 0
            );
        }
        foreach (Geary.RFC822.Message sub_message in sub_messages) {
            ConversationMessage attached_message =
                new ConversationMessage(sub_message, false);
            connect_message_view_signals(attached_message);
            attached_message.web_view.add_inline_resources(cid_resources);
            this.sub_messages.add(attached_message);
            this._attached_messages.add(attached_message);
        }
    }

    /**
     * Starts loading the complete email.
     *
     * This method will load the avatar and message body for the
     * primary message and any attached messages, as well as
     * attachment names, types and icons.
     */
    public async void start_loading(Cancellable load_cancelled) {
        message_view_iterator().foreach((view) => {
                if (!load_cancelled.is_cancelled()) {
                    primary_message.load_message_body.begin(load_cancelled);
                }
                view.load_avatar.begin(
                    GearyApplication.instance.controller.avatar_session,
                    load_cancelled
                );

                return !load_cancelled.is_cancelled();
            });

        // Only load attachments once the web views have finished
        // loading, since we want to know if any attachments marked as
        // being inline were actually not displayed inline, and hence
        // need to be displayed as if they were attachments.
        if (!load_cancelled.is_cancelled()) {
            if (this.message_bodies_loaded) {
                yield load_attachments(load_cancelled);
            } else {
                this.notify["message-bodies-loaded"].connect(() => {
                        load_attachments.begin(load_cancelled);
                    });
            }
        }
    }

    /**
     * Shows the complete message: headers, body and attachments.
     */
    public void expand_email(bool include_transitions=true) {
        is_collapsed = false;
        update_email_state();
        attachments_button.set_sensitive(true);
        email_menubutton.set_sensitive(true);
        primary_message.show_message_body(include_transitions);
        foreach (ConversationMessage attached in this._attached_messages) {
            attached.show_message_body(include_transitions);
        }
    }

    /**
     * Hides the complete message, just showing the header preview.
     */
    public void collapse_email() {
        is_collapsed = true;
        update_email_state();
        attachments_button.set_sensitive(false);
        email_menubutton.set_sensitive(false);
        primary_message.hide_message_body();
        foreach (ConversationMessage attached in this._attached_messages) {
            attached.hide_message_body();
        }
    }

    /**
     * Updates the current email's flags and dependent UI state.
     */
    public void update_flags(Geary.Email email) {
        this.email.set_flags(email.email_flags);
        update_email_state();
    }

    /**
     * Returns user-selected body HTML from a message, if any.
     */
    public async string? get_selection_for_quoting() {
        string? selection = null;
        if (this.body_selection_message != null) {
            try {
                selection =
                   yield this.body_selection_message.web_view.get_selection_for_quoting();
            } catch (Error err) {
                debug("Failed to get selection for quoting: %s", err.message);
            }
        }
        return selection;
    }

    /**
     * Returns user-selected body text from a message, if any.
     */
    public async string? get_selection_for_find() {
        string? selection = null;
        if (this.body_selection_message != null) {
            try {
                selection =
                   yield this.body_selection_message.web_view.get_selection_for_find();
            } catch (Error err) {
                debug("Failed to get selection for find: %s", err.message);
            }
        }
        return selection;
    }

    /**
     * Returns a new Iterable over all message views in this email view
     */
    internal Gee.Iterator<ConversationMessage> message_view_iterator() {
        return new MessageViewIterator(this);
    }

    private SimpleAction add_action(string name, bool enabled = true) {
        SimpleAction action = new SimpleAction(name, null);
        action.set_enabled(enabled);
        message_actions.add_action(action);
        return action;
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action = this.message_actions.lookup(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private void connect_message_view_signals(ConversationMessage view) {
        view.flag_remote_images.connect(on_flag_remote_images);
        view.remember_remote_images.connect(on_remember_remote_images);
        view.web_view.inline_resource_loaded.connect((id) => {
                this.inlined_content_ids.add(id);
            });
        view.web_view.notify["load-status"].connect(() => {
                bool all_loaded = true;
                message_view_iterator().foreach((view) => {
                        if (!view.web_view.is_loaded) {
                            all_loaded = false;
                            return false;
                        }
                        return true;
                    });
                if (all_loaded == true) {
                    this.message_bodies_loaded = true;
                }
            });
        view.web_view.selection_changed.connect((has_selection) => {
                this.body_selection_message = has_selection ? view : null;
                body_selection_changed(has_selection);
            });
    }

    private void update_email_state() {
        Geary.EmailFlags? flags = this.email.email_flags;
        Gtk.StyleContext style = get_style_context();

        bool is_unread = (flags != null && flags.is_unread());
        set_action_enabled(ACTION_MARK_READ, is_unread);
        set_action_enabled(ACTION_MARK_UNREAD, !is_unread);
        set_action_enabled(ACTION_MARK_UNREAD_DOWN, !is_unread);
        if (is_unread) {
            style.add_class(UNREAD_CLASS);
        } else {
            style.remove_class(UNREAD_CLASS);
        }

        bool is_flagged = (flags != null && flags.is_flagged());
        set_action_enabled(ACTION_STAR, !this.is_collapsed && !is_flagged);
        set_action_enabled(ACTION_UNSTAR, !this.is_collapsed && is_flagged);
        if (is_flagged) {
            style.add_class(STARRED_CLASS);
            star_button.hide();
            unstar_button.show();
        } else {
            style.remove_class(STARRED_CLASS);
            star_button.show();
            unstar_button.hide();
        }

        if (flags != null && flags.is_outbox_sent()) {
            this.not_saved_infobar.show();
        }
    }

    private async void load_attachments(Cancellable load_cancelled) {
        // Determine if we have any attachments to be displayed. This
        // relies on the primary and any attached message bodies
        // having being already loaded, so that we know which
        // attachments have been shown inline and hence do not need to
        // be included here.
        foreach (Geary.Attachment attachment in email.attachments) {
            if (!(attachment.content_id in this.inlined_content_ids)) {
                Geary.Mime.DispositionType? disposition = null;
                if (attachment.content_disposition != null) {
                    disposition = attachment.content_disposition.disposition_type;
                }
                // Display both any attachment and inline parts that
                // have already not been inlined. Although any inline
                // parts should be referred to by other content in a
                // multipart/related or multipart/alternative
                // container, or inlined if in a multipart/mixed
                // container, this cannot be not guaranteed. C.f. Bug
                // 769868.
                if (disposition != null &&
                    disposition == Geary.Mime.DispositionType.ATTACHMENT ||
                    disposition == Geary.Mime.DispositionType.INLINE) {
                    this.displayed_attachments.add(attachment);
                }
            }
        }

        // Now we can actually show the attachments, if any
        if (!this.displayed_attachments.is_empty) {
            this.attachments_button.show();
            this.attachments_button.set_sensitive(!this.is_collapsed);
            this.primary_message.body.add(this.attachments);

            if (this.displayed_attachments.size > 1) {
                this.select_all_attachments.show();
                set_action_enabled(ACTION_SELECT_ALL_ATTACHMENTS, true);
            }

            foreach (Geary.Attachment attachment in this.displayed_attachments) {
                if (load_cancelled.is_cancelled()) {
                    return;
                }
                AttachmentView view = new AttachmentView(attachment);
                this.attachments_view.add(view);
                yield view.load_icon(load_cancelled);
            }
        }
    }

    internal Gee.Collection<Geary.Attachment> get_selected_attachments() {
        Gee.LinkedList<Geary.Attachment> selected =
            new Gee.LinkedList<Geary.Attachment>();
        foreach (Gtk.FlowBoxChild child in
                 this.attachments_view.get_selected_children()) {
            selected.add(((AttachmentView) child.get_child()).attachment);
        }
        return selected;
    }

    private void print() {
        // XXX This isn't anywhere near good enough - headers aren't
        // being printed.
        WebKit.PrintOperation op = new WebKit.PrintOperation(
            this.primary_message.web_view
        );
        Gtk.Window? window = get_toplevel() as Gtk.Window;
        if (op.run_dialog(window) == WebKit.PrintOperationResponse.PRINT) {
            op.print();
        }
    }

    private void on_flag_remote_images(ConversationMessage view) {
        // XXX check we aren't already auto loading the image
        mark_email(Geary.EmailFlags.LOAD_REMOTE_IMAGES, null);
    }


    private void on_remember_remote_images(ConversationMessage view) {
        Geary.RFC822.MailboxAddress? sender = view.message.get_primary_originator();
        if (sender == null) {
            debug("Couldn't find sender for message: %s", email.id.to_string());
            return;
        }

        Geary.Contact? contact = contact_store.get_by_rfc822(
            view.message.get_primary_originator()
        );
        if (contact == null) {
            debug("Couldn't find contact for %s", sender.to_string());
            return;
        }

        Geary.ContactFlags flags = new Geary.ContactFlags();
        flags.add(Geary.ContactFlags.ALWAYS_LOAD_REMOTE_IMAGES);
        Gee.ArrayList<Geary.Contact> contact_list = new Gee.ArrayList<Geary.Contact>();
        contact_list.add(contact);
        contact_store.mark_contacts_async.begin(contact_list, flags, null);
    }

    [GtkCallback]
    private void on_attachments_child_activated(Gtk.FlowBox view,
                                                Gtk.FlowBoxChild child) {
        attachments_activated(
            Geary.iterate<Geary.Attachment>(
                ((AttachmentView) child.get_child()).attachment
            ).to_array_list()
        );
    }

    [GtkCallback]
    private void on_attachments_selected_changed(Gtk.FlowBox view) {
        uint len = view.get_selected_children().length();
        bool not_empty = len > 0;
        set_action_enabled(ACTION_OPEN_ATTACHMENTS, not_empty);
        set_action_enabled(ACTION_SAVE_ATTACHMENTS, not_empty);
        set_action_enabled(ACTION_SELECT_ALL_ATTACHMENTS,
                           len < this.displayed_attachments.size);
    }

}
