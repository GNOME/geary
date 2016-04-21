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

    private const int ATTACHMENT_ICON_SIZE = 32;
    private const int ATTACHMENT_PREVIEW_SIZE = 64;


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

    [GtkChild]
    private Gtk.Box action_box;

    [GtkChild]
    private Gtk.Image attachment_icon;

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
    private Gtk.ListStore attachments_model;

    // Fired on link activation in the web_view
    public signal void link_activated(string link);

    // Fired on attachment activation
    public signal void attachment_activated(Geary.Attachment attachment);

    // Fired the edit draft button is clicked.
    public signal void edit_draft(Geary.Email message);


    public ConversationEmail(Geary.Email email,
                             Geary.ContactStore contact_store,
                             bool is_draft) {
        this.email = email;
        this.contact_store = contact_store;

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
        primary_message.summary_box.pack_start(action_box, false, false, 0);

        email_menubutton.set_menu_model(build_message_menu(email));
        email_menubutton.set_sensitive(false);

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
        //  get_style_context().add_class("sent");
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
        yield primary_message.load_message_body(load_cancelled);
        foreach (ConversationMessage message in conversation_messages) {
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

    private MenuModel build_message_menu(Geary.Email email) {
        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menu.ui"
        );

        MenuModel menu = (MenuModel) builder.get_object("conversation_message_menu");

        // menu.selection_done.connect(on_message_menu_selection_done);

        // int displayed = displayed_attachments(email);
        // if (displayed > 0) {
        //     string mnemonic = ngettext("Save A_ttachment...", "Save All A_ttachments...",
        //         displayed);
        //     Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(mnemonic);
        //     save_all_item.activate.connect(() => save_attachments(email.attachments));
        //     menu.append(save_all_item);
        //     menu.append(new Gtk.SeparatorMenuItem());
        // }

        // if (!in_drafts_folder()) {
        //     // Reply to a message.
        //     Gtk.MenuItem reply_item = new Gtk.MenuItem.with_mnemonic(_("_Reply"));
        //     reply_item.activate.connect(() => reply_to_message(email));
        //     menu.append(reply_item);

        //     // Reply to all on a message.
        //     Gtk.MenuItem reply_all_item = new Gtk.MenuItem.with_mnemonic(_("Reply to _All"));
        //     reply_all_item.activate.connect(() => reply_all_message(email));
        //     menu.append(reply_all_item);

        //     // Forward a message.
        //     Gtk.MenuItem forward_item = new Gtk.MenuItem.with_mnemonic(_("_Forward"));
        //     forward_item.activate.connect(() => forward_message(email));
        //     menu.append(forward_item);
        // }

        // if (menu.get_children().length() > 0) {
        //     // Separator.
        //     menu.append(new Gtk.SeparatorMenuItem());
        // }

        // // Mark as read/unread.
        // if (email.is_unread().to_boolean(false)) {
        //     Gtk.MenuItem mark_read_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Read"));
        //     mark_read_item.activate.connect(() => on_mark_read_message(email));
        //     menu.append(mark_read_item);
        // } else {
        //     Gtk.MenuItem mark_unread_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Unread"));
        //     mark_unread_item.activate.connect(() => on_mark_unread_message(email));
        //     menu.append(mark_unread_item);

        //     if (messages.size > 1 && messages.last() != email) {
        //         Gtk.MenuItem mark_unread_from_here_item = new Gtk.MenuItem.with_mnemonic(
        //             _("Mark Unread From _Here"));
        //         mark_unread_from_here_item.activate.connect(() => on_mark_unread_from_here(email));
        //         menu.append(mark_unread_from_here_item);
        //     }
        // }

        // // Print a message.
        // Gtk.MenuItem print_item = new Gtk.MenuItem.with_mnemonic(Stock._PRINT_MENU);
        // print_item.activate.connect(() => on_print_message(email));
        // menu.append(print_item);

        // // Separator.
        // menu.append(new Gtk.SeparatorMenuItem());

        // // View original message source.
        // Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("_View Source"));
        // view_source_item.activate.connect(() => on_view_source(email));
        // menu.append(view_source_item);

        return menu;
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

    private void update_email_state(bool include_transitions=true) {
        Geary.EmailFlags flags = email.email_flags;
        Gtk.StyleContext style = get_style_context();

        if (flags.is_unread()) {
            style.add_class("geary_unread");
        } else {
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

    private void on_flag_remote_images(ConversationMessage view) {
        // XXX check we aren't already auto loading the image
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.LOAD_REMOTE_IMAGES);
        //get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(),
        //flags, null);
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
        Gtk.TreeIter iter;
        Value attachment_id;

        attachments_model.get_iter(out iter, path);
        attachments_model.get_value(iter, 2, out attachment_id);

        Geary.Attachment? attachment = null;
        try {
            attachment = email.get_attachment(attachment_id.get_string());
        } catch (Error error) {
            warning("Error getting attachment: %s", error.message);
        }

        if (attachment != null) {
            attachment_activated(attachment);
        }
    }

    // private void save_attachment(Geary.Attachment attachment) {
    //     Gee.List<Geary.Attachment> attachments = new Gee.ArrayList<Geary.Attachment>();
    //     attachments.add(attachment);
    //     get_viewer().save_attachments(attachments);
    // }

    // private void on_mark_read_message(Geary.Email message) {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.UNREAD);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), null, flags);
    //     mark_manual_read(message.id);
    // }

    // private void on_mark_unread_message(Geary.Email message) {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.UNREAD);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), flags, null);
    //     mark_manual_read(message.id);
    // }

    // private void on_mark_unread_from_here(Geary.Email message) {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.UNREAD);

    //     Gee.Iterator<Geary.Email>? iter = messages.iterator_at(message);
    //     if (iter == null) {
    //         warning("Email not found in message list");

    //         return;
    //     }

    //     // Build a list of IDs to mark.
    //     Gee.ArrayList<Geary.EmailIdentifier> to_mark = new Gee.ArrayList<Geary.EmailIdentifier>();
    //     to_mark.add(message.id);
    //     while (iter.next())
    //         to_mark.add(iter.get().id);

    //     get_viewer().mark_messages(to_mark, flags, null);
    //     foreach(Geary.EmailIdentifier id in to_mark)
    //         mark_manual_read(id);
    // }

    // private void on_print_message(Geary.Email message) {
    //     try {
    //         email_to_element.get(message.id).get_class_list().add("print");
    //         web_view.get_main_frame().print();
    //         email_to_element.get(message.id).get_class_list().remove("print");
    //     } catch (GLib.Error error) {
    //         debug("Hiding elements for printing failed: %s", error.message);
    //     }
    // }

    // private void flag_message() {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.FLAGGED);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), flags, null);
    // }

    // private void unflag_message() {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.FLAGGED);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), null, flags);
    // }

    // private void show_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
    //     attachment_menu = build_attachment_menu(email, attachment);
    //     attachment_menu.show_all();
    //     attachment_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    // }

    // private Gtk.Menu build_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
    //     Gtk.Menu menu = new Gtk.Menu();
    //     menu.selection_done.connect(on_attachment_menu_selection_done);

    //     Gtk.MenuItem save_attachment_item = new Gtk.MenuItem.with_mnemonic(_("_Save As..."));
    //     save_attachment_item.activate.connect(() => save_attachment(attachment));
    //     menu.append(save_attachment_item);

    //     if (displayed_attachments(email) > 1) {
    //         Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(_("Save All A_ttachments..."));
    //         save_all_item.activate.connect(() => save_attachments(email.attachments));
    //         menu.append(save_all_item);
    //     }

    //     return menu;
    // }

    private async void load_attachments(Cancellable load_cancelled) {
        Gee.List<Geary.Attachment> displayed_attachments =
            new Gee.LinkedList<Geary.Attachment>();

        // Do we have any attachments to display?
        foreach (Geary.Attachment attachment in email.attachments) {
            if (!(attachment.content_id in inlined_content_ids) &&
                attachment.content_disposition.disposition_type ==
                    Geary.Mime.DispositionType.ATTACHMENT) {
                displayed_attachments.add(attachment);
            }
        }

        if (displayed_attachments.is_empty) {
            return;
        }

        // Show attachments container. Would like to do this in the
        // ctor but we don't know at that point if any attachments
        // will be displayed inline
        attachment_icon.set_visible(true);
        primary_message.body_box.pack_start(attachments_box, false, false, 0);

        // Add each displayed attachment to the icon view
        foreach (Geary.Attachment attachment in displayed_attachments) {
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
                2, attachment.id,
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
        //int window_scale = get_window().get_scale_factor();
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
                    warning("Unsupported attachment icon type: %s\n",
                            icon.get_type().name());
                }
            }
        } catch (Error error) {
            warning("Failed to load icon for attachment '%s': %s",
                    attachment.id,
                    error.message);
        }

        return pixbuf;
    }

    // private void on_view_source(Geary.Email message) {
    //     string source = message.header.buffer.to_string() + message.body.buffer.to_string();

    //     try {
    //         string temporary_filename;
    //         int temporary_handle = FileUtils.open_tmp("geary-message-XXXXXX.txt",
    //             out temporary_filename);
    //         FileUtils.set_contents(temporary_filename, source);
    //         FileUtils.close(temporary_handle);

    //         // ensure this file is only readable by the user ... this needs to be done after the
    //         // file is closed
    //         FileUtils.chmod(temporary_filename, (int) (Posix.S_IRUSR | Posix.S_IWUSR));

    //         string temporary_uri = Filename.to_uri(temporary_filename, null);
    //         Gtk.show_uri(web_view.get_screen(), temporary_uri, Gdk.CURRENT_TIME);
    //     } catch (Error error) {
    //         ErrorDialog dialog = new ErrorDialog(GearyApplication.instance.controller.main_window,
    //             _("Failed to open default text editor."), error.message);
    //         dialog.run();
    //     }
    // }

}
