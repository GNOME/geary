/*
 * Copyright 2011-2015 Yorba Foundation
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an email in a conversation.
 *
 * This widget corresponds to {@link Geary.Email}, displaying the
 * email's primary message (a {@link Geary.RFC822.Message}), any
 * sub-messages (also instances of {@link Geary.RFC822.Message}) and
 * attachments. The RFC822 messages are themselves displayed by {@link
 * ConversationMessage}.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-email.ui")]
public class ConversationEmail : Gtk.Box {


    /**
     * Information related to a specific attachment.
     */
    public class AttachmentInfo : GLib.Object {
        // Extends GObject since we put it in a ListStore

        public Geary.Attachment attachment { get; private set; }
        public AppInfo? app { get; internal set; default = null; }


        internal AttachmentInfo(Geary.Attachment attachment) {
            this.attachment = attachment;
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
    private const string ACTION_STAR = "star";
    private const string ACTION_UNSTAR = "unstar";
    private const string ACTION_VIEW_SOURCE = "view_source";


    // The email message being displayed
    public Geary.Email email { get; private set; }

    // Is the message body shown or not?
    public bool is_message_body_visible = false;

    // Widget displaying the email's primary message
    public ConversationMessage primary_message { get; private set; }

    // Contacts for the email's account
    private Geary.ContactStore contact_store;

    // Messages that have been attached to this one
    private Gee.List<ConversationMessage> conversation_messages =
        new Gee.LinkedList<ConversationMessage>();

    // Attachment ids that have been displayed inline
    private Gee.HashSet<string> inlined_content_ids = new Gee.HashSet<string>();

    // A subset of the message's attachments that are displayed in the
    // attachments view
    Gee.List<AttachmentInfo> displayed_attachments =
        new Gee.LinkedList<AttachmentInfo>();

    // A subset of the message's attachments selected by the user
    Gee.Set<AttachmentInfo> selected_attachments =
        new Gee.HashSet<AttachmentInfo>();

    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    [GtkChild]
    private Gtk.Box action_box;

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
    private Gtk.Box sub_messages_box;

    [GtkChild]
    private Gtk.Box attachments_box;

    [GtkChild]
    private Gtk.IconView attachments_view;

    [GtkChild]
    private Gtk.ListStore attachments_model;

    private Gtk.Menu attachments_menu;

    // Fired when the user clicks "reply" in the message menu.
    public signal void reply_to_message(Geary.Email message);

    // Fired when the user clicks "reply all" in the message menu.
    public signal void reply_all_message(Geary.Email message);

    // Fired when the user clicks "forward" in the message menu.
    public signal void forward_message(Geary.Email message);

    // Fired when the user updates the message's flags.
    public signal void mark_email(
        Geary.Email email, Geary.NamedFlag? to_add, Geary.NamedFlag? to_remove
    );

    // Fired when the user updates all message's flags from this down.
    public signal void mark_email_from(
        Geary.Email email, Geary.NamedFlag? to_add, Geary.NamedFlag? to_remove
    );

    // Fired on message image save action is activated
    public signal void save_image(string? filename, Geary.Memory.Buffer buffer);

    // Fired on link activation in the web_view
    public signal void link_activated(string link);

    // Fired on attachment activation
    public signal void attachments_activated(Gee.Collection<AttachmentInfo> attachments);

    // Fired when the save attachments action is activated
    public signal void save_attachments(Gee.Collection<AttachmentInfo> attachments);

    // Fired the edit draft button is clicked.
    public signal void edit_draft(Geary.Email email);

    // Fired when the view source action is activated
    public signal void view_source(Geary.Email email);


    public ConversationEmail(Geary.Email email,
                             Geary.ContactStore contact_store,
                             bool is_draft) {
        this.email = email;
        this.contact_store = contact_store;

        add_action(ACTION_FORWARD).activate.connect(() => {
                forward_message(this.email);
            });
        add_action(ACTION_PRINT).activate.connect(() => {
                print();
            });
        add_action(ACTION_MARK_READ).activate.connect(() => {
                mark_email(this.email, null, Geary.EmailFlags.UNREAD);
            });
        add_action(ACTION_MARK_UNREAD).activate.connect(() => {
                mark_email(this.email, Geary.EmailFlags.UNREAD, null);
            });
        add_action(ACTION_MARK_UNREAD_DOWN).activate.connect(() => {
                mark_email_from(this.email, Geary.EmailFlags.UNREAD, null);
            });
        add_action(ACTION_OPEN_ATTACHMENTS).activate.connect(() => {
                attachments_activated(selected_attachments);
            });
        add_action(ACTION_REPLY_ALL).activate.connect(() => {
                reply_all_message(this.email);
            });
        add_action(ACTION_REPLY_SENDER).activate.connect(() => {
                reply_to_message(this.email);
            });
        add_action(ACTION_SAVE_ATTACHMENTS).activate.connect(() => {
                save_attachments(selected_attachments);
            });
        add_action(ACTION_SAVE_ALL_ATTACHMENTS).activate.connect(() => {
                save_attachments(displayed_attachments);
            });
        add_action(ACTION_STAR).activate.connect(() => {
                mark_email(this.email, Geary.EmailFlags.FLAGGED, null);
            });
        add_action(ACTION_UNSTAR).activate.connect(() => {
                mark_email(this.email, null, Geary.EmailFlags.FLAGGED);
            });
        add_action(ACTION_VIEW_SOURCE).activate.connect(() => {
                view_source(this.email);
            });
        insert_action_group("eml", message_actions);

        Geary.RFC822.Message message;
        try {
            message = email.get_message();
        } catch (Error error) {
            debug("Error loading primary message: %s", error.message);
            return;
        }

        primary_message = new ConversationMessage(
            message,
            contact_store,
            email.load_remote_images().is_certain()
        );
        primary_message.flag_remote_images.connect(on_flag_remote_images);
        primary_message.remember_remote_images.connect(on_remember_remote_images);
        primary_message.attachment_displayed_inline.connect((id) => {
                inlined_content_ids.add(id);
            });
        primary_message.web_view.link_selected.connect((link) => {
                link_activated(link);
            });
        primary_message.save_image.connect((filename, buffer) => {
                save_image(filename, buffer);
            });
        primary_message.summary_box.pack_start(action_box, false, false, 0);

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-email-menus.ui"
        );
        email_menubutton.set_menu_model((MenuModel) builder.get_object("email_menu"));
        email_menubutton.set_sensitive(false);

        attachments_menu = new Gtk.Menu.from_model(
            (MenuModel) builder.get_object("attachments_menu")
        );
        attachments_menu.attach_to_widget(this, null);

        primary_message.infobar_box.pack_start(draft_infobar, false, false, 0);
        if (is_draft) {
            draft_infobar.show();
            draft_infobar.response.connect((infobar, response_id) => {
                    if (response_id == 1) { edit_draft(email); }
                });
        }

        primary_message.infobar_box.pack_start(not_saved_infobar, false, false, 0);

        // if (email.from != null && email.from.contains_normalized(current_account_information.email)) {
        //  // XXX set a RO property?
        //  get_style_context().add_class("geary_sent");
        // }

        // Add sub_messages container and message viewers if there are any
        Gee.List<Geary.RFC822.Message> sub_messages = message.get_sub_messages();
        if (sub_messages.size > 0) {
            primary_message.body_box.pack_start(sub_messages_box, false, false, 0);
        }
        foreach (Geary.RFC822.Message sub_message in sub_messages) {
            ConversationMessage conversation_message =
                new ConversationMessage(sub_message, contact_store, false);
            sub_messages_box.pack_start(conversation_message, false, false, 0);
            this.conversation_messages.add(conversation_message);
        }

        pack_start(primary_message, true, true, 0);
        update_email_state(false);
    }

    public async void start_loading(Cancellable load_cancelled) {
        yield primary_message.load_avatar(
            GearyApplication.instance.controller.avatar_session,
            load_cancelled
        );
        yield primary_message.load_message_body(load_cancelled);
        foreach (ConversationMessage message in conversation_messages) {
            yield message.load_avatar(
                GearyApplication.instance.controller.avatar_session,
                load_cancelled
            );
            yield message.load_message_body(load_cancelled);
        }
        yield load_attachments(load_cancelled);
    }

    public void expand_email(bool include_transitions=true) {
        is_message_body_visible = true;
        get_style_context().add_class("geary_show_body");
        star_button.set_sensitive(true);
        unstar_button.set_sensitive(true);
        email_menubutton.set_sensitive(true);
        primary_message.show_message_body(include_transitions);
    }

    public void collapse_email() {
        is_message_body_visible = false;
        get_style_context().remove_class("geary_show_body");
        star_button.set_sensitive(false);
        unstar_button.set_sensitive(false);
        email_menubutton.set_sensitive(false);
        primary_message.hide_message_body();
    }

    public void update_flags(Geary.Email email) {
        this.email.set_flags(email.email_flags);
        update_email_state();
    }

    public bool is_manual_read() {
        return get_style_context().has_class("geary_manual_read");
    }

    public void mark_manual_read() {
        get_style_context().add_class("geary_manual_read");
    }

    private SimpleAction add_action(string name) {
        SimpleAction action = new SimpleAction(name, null);
        message_actions.add_action(action);
        return action;
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action = this.message_actions.lookup(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private void update_email_state(bool include_transitions=true) {
        Geary.EmailFlags flags = email.email_flags;
        Gtk.StyleContext style = get_style_context();

        if (flags.is_unread()) {
            set_action_enabled(ACTION_MARK_READ, true);
            set_action_enabled(ACTION_MARK_UNREAD, false);
            set_action_enabled(ACTION_MARK_UNREAD_DOWN, false);
            style.add_class("geary_unread");
        } else {
            set_action_enabled(ACTION_MARK_READ, false);
            set_action_enabled(ACTION_MARK_UNREAD, true);
            set_action_enabled(ACTION_MARK_UNREAD_DOWN, true);
            style.remove_class("geary_unread");
        }

        if (flags.is_flagged()) {
            style.add_class("geary_starred");
            star_button.hide();
            unstar_button.show();
        } else {
            style.remove_class("geary_starred");
            star_button.show();
            unstar_button.hide();
        }

        if (flags.is_outbox_sent()) {
            not_saved_infobar.show();
        }
    }

    private void print() {
        // XXX this isn't anywhere near good enough
        primary_message.web_view.get_main_frame().print();
    }

    private void on_flag_remote_images(ConversationMessage view) {
        // XXX check we aren't already auto loading the image
        mark_email(email, Geary.EmailFlags.LOAD_REMOTE_IMAGES, null);
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
    private void on_attachments_view_activated(Gtk.IconView view, Gtk.TreePath path) {
        AttachmentInfo attachment_info = attachment_info_for_view_path(path);
        attachments_activated(
            Geary.iterate<AttachmentInfo>(attachment_info).to_array_list()
        );
    }

    [GtkCallback]
    private void on_attachments_view_selection_changed() {
        selected_attachments.clear();
        List<Gtk.TreePath> selected = attachments_view.get_selected_items();
        selected.foreach((path) => {
                selected_attachments.add(attachment_info_for_view_path(path));
            });
    }

    [GtkCallback]
    private bool on_attachments_view_button_press_event(Gdk.EventButton event) {
        if (event.button != Gdk.BUTTON_SECONDARY) {
            return false;
        }

        Gtk.TreePath path = attachments_view.get_path_at_pos(
            (int) event.x, (int) event.y
            );
        AttachmentInfo attachment = attachment_info_for_view_path(path);
        if (!selected_attachments.contains(attachment)) {
            attachments_view.unselect_all();
            attachments_view.select_path(path);
        }
        attachments_menu.popup(null, null, null, event.button, event.time);
        return false;
    }

    private AttachmentInfo attachment_info_for_view_path(Gtk.TreePath path) {
        Gtk.TreeIter iter;
        attachments_model.get_iter(out iter, path);
        Value info_value;
        attachments_model.get_value(iter, 2, out info_value);
        AttachmentInfo info = (AttachmentInfo) info_value.dup_object();
        info_value.unset();
        return info;
    }

    private async void load_attachments(Cancellable load_cancelled) {
        // Do we have any attachments to be displayed?
        foreach (Geary.Attachment attachment in email.attachments) {
            if (!(attachment.content_id in inlined_content_ids) &&
                attachment.content_disposition.disposition_type ==
                    Geary.Mime.DispositionType.ATTACHMENT) {
                displayed_attachments.add(new AttachmentInfo(attachment));
            }
        }

        if (displayed_attachments.is_empty) {
            set_action_enabled(ACTION_OPEN_ATTACHMENTS, false);
            set_action_enabled(ACTION_SAVE_ATTACHMENTS, false);
            set_action_enabled(ACTION_SAVE_ALL_ATTACHMENTS, false);
            return;
        }

        // Show attachments container. Would like to do this in the
        // ctor but we don't know at that point if any attachments
        // will be displayed inline.
        attachments_button.set_visible(true);
        primary_message.body_box.pack_start(attachments_box, false, false, 0);

        // Add each displayed attachment to the icon view
        foreach (AttachmentInfo attachment_info in displayed_attachments) {
            Geary.Attachment attachment = attachment_info.attachment;

            attachment_info.app = AppInfo.get_default_for_type(
                attachment.content_type.get_mime_type(), false
            );

            Gdk.Pixbuf? icon =
                yield load_attachment_icon(attachment, load_cancelled);
            string file_name = null;
            if (attachment.has_supplied_filename) {
                file_name = attachment.file.get_basename();
            }
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
                file_name = ContentType.get_description(
                    attachment.content_type.get_mime_type()
                );
            }
            string file_size = Files.get_filesize_as_string(attachment.filesize);

            Gtk.TreeIter iter;
            attachments_model.append(out iter);
            attachments_model.set(
                iter,
                0, icon,
                1, Markup.printf_escaped("%s\n%s", file_name, file_size),
                2, attachment_info,
                -1
            );
        }
    }

    private async Gdk.Pixbuf? load_attachment_icon(Geary.Attachment attachment,
                                                   Cancellable load_cancelled) {
        Geary.Mime.ContentType content_type = attachment.content_type;
        Gdk.Pixbuf? pixbuf = null;

        // Due to Bug 65167, for retina/highdpi displays with
        // window_scale == 2, GtkCellRendererPixbuf will draw the
        // pixbuf twice as large and blurry, so clamp it to 1 for now
        // - this at least gives is the correct size icons, but still
        // blurry.
        //int window_scale = get_scale_factor();
        int window_scale = 1;
        try {
            // If the file is an image, use it. Otherwise get the icon
            // for this mime_type.
            if (content_type.has_media_type("image")) {
                // Get a thumbnail for the image.
                // TODO Generate and save the thumbnail when
                // extracting the attachments rather than when showing
                // them in the viewer.
                int preview_size = ATTACHMENT_PREVIEW_SIZE * window_scale;
                InputStream stream = yield attachment.file.read_async(
                    Priority.DEFAULT,
                    load_cancelled
                );
                pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                    stream, preview_size, preview_size, true, load_cancelled
                );
                pixbuf = pixbuf.apply_embedded_orientation();
            } else {
                // Load the icon for this mime type.
                string gio_content_type =
                   ContentType.from_mime_type(content_type.get_mime_type());
                Icon icon = ContentType.get_icon(gio_content_type);
                Gtk.IconTheme theme = Gtk.IconTheme.get_default();

                // XXX GTK 3.14 We should be able to replace the
                // ThemedIcon/LoadableIcon/other cases below with
                // simply this:
                // Gtk.IconInfo? icon_info = theme.lookup_by_gicon_for_scale(
                //     icon, ATTACHMENT_ICON_SIZE, window_scale
                // );
                // pixbuf = yield icon_info.load_icon_async(load_cancelled);

                if (icon is ThemedIcon) {
                    Gtk.IconInfo? icon_info = null;
                    foreach (string name in ((ThemedIcon) icon).names) {
                        icon_info = theme.lookup_icon_for_scale(
                            name, ATTACHMENT_ICON_SIZE, window_scale, 0
                        );
                        if (icon_info != null) {
                            break;
                        }
                    }
                    if (icon_info == null) {
                        icon_info = theme.lookup_icon_for_scale(
                            "x-office-document", ATTACHMENT_ICON_SIZE, window_scale, 0
                        );
                    }
                    pixbuf = yield icon_info.load_icon_async(load_cancelled);
                } else if (icon is LoadableIcon) {
                    InputStream stream = yield ((LoadableIcon) icon).load_async(
                        ATTACHMENT_ICON_SIZE, load_cancelled
                    );
                    int icon_size = ATTACHMENT_ICON_SIZE * window_scale;
                    pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                        stream, icon_size, icon_size, true, load_cancelled
                    );
                } else {
                    debug("Unsupported attachment icon type: %s\n",
                            icon.get_type().name());
                }
            }
        } catch (Error error) {
            debug("Failed to load icon for attachment '%s': %s",
                    attachment.id,
                    error.message);
        }

        return pixbuf;
    }

}
