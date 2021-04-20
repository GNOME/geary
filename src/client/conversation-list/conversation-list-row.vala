[GtkTemplate (ui = "/org/gnome/Geary/conversation-list-row.ui")]
internal class ConversationList.Row : Gtk.ListBoxRow {

    private Gee.List<Geary.RFC822.MailboxAddress>? user_accounts  {
        owned get {
            return conversation.base_folder.account.information.sender_mailboxes;
        }
    }

    [GtkChild] unowned Gtk.Label preview;
    [GtkChild] unowned Gtk.Box preview_row;
    [GtkChild] unowned Gtk.Label subject;
    [GtkChild] unowned Gtk.Label participants;
    [GtkChild] unowned Gtk.Label date;
    [GtkChild] unowned Gtk.Button unread;
    [GtkChild] unowned Gtk.Button flagged;
    [GtkChild] unowned Gtk.Label count_badge;

    [GtkChild] unowned Gtk.Image unread_icon;
    [GtkChild] unowned Gtk.Image read_icon;
    [GtkChild] unowned Gtk.Image flagged_icon;
    [GtkChild] unowned Gtk.Image unflagged_icon;

    internal Geary.App.Conversation conversation;
    private Application.Configuration config;
    private DateTime? recv_time;

    internal signal void toggle_flag(ConversationList.Row row,
                                   Geary.NamedFlag flag);

    internal signal void secondary_clicked(ConversationList.Row row,
                                         Gdk.EventButton event);


    internal Row(Application.Configuration config, Geary.App.Conversation conversation) {
        this.config = config;
        this.conversation = conversation;

        Geary.Email? last_email = conversation.get_latest_recv_email(
                                        Geary.App.Conversation.Location.ANYWHERE);
        if (last_email != null) {
            var text = Util.Email.strip_subject_prefixes(last_email);
            this.subject.set_text(text);
            this.preview.set_text(last_email.get_preview_as_string());
            this.recv_time = last_email.properties.date_received.to_local();
            refresh_time();
        }

        this.participants.set_markup(get_participants());

        var count = conversation.get_count();
        if (count > 1) {
            this.count_badge.set_text(conversation.get_count().to_string());
        } else {
            this.count_badge.hide();
        }

        conversation.email_flags_changed.connect(update_flags);
        update_flags(null);

        config.bind(Application.Configuration.DISPLAY_PREVIEW_KEY,
                  this.preview_row, "visible");

    }

    internal void refresh_time() {
        if (this.recv_time != null) {
            // conversation list store sorts by date-received, so display that
            // instead of the sent time
            this.date.set_text(Util.Date.pretty_print(
                this.recv_time,
                this.config.clock_format
            ));
        }
    }


    private void update_flags(Geary.Email? email) {
        if (conversation.is_unread()) {
            get_style_context().add_class("unread");
            unread.set_image(unread_icon);
        } else {
            get_style_context().remove_class("unread");
            unread.set_image(read_icon);
        }

        if (conversation.is_flagged()) {
            get_style_context().add_class("flagged");
            flagged.set_image(flagged_icon);
        } else {
            get_style_context().remove_class("flagged");
            flagged.set_image(unflagged_icon);
        }
    }

    [GtkCallback] private void mark_unread() {
        toggle_flag(this, Geary.EmailFlags.UNREAD);
    }

    [GtkCallback] private void mark_flagged() {
        toggle_flag(this, Geary.EmailFlags.FLAGGED);
    }

    private string get_participants() {
        var participants = new Gee.ArrayList<Participant>();
        Gee.List<Geary.Email> emails = conversation.get_emails(
                          Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING);

        foreach (Geary.Email message in emails) {
            Geary.RFC822.MailboxAddresses? addresses =
                conversation.base_folder.used_as.is_outgoing()
                ? new Geary.RFC822.MailboxAddresses.single(Util.Email.get_primary_originator(message))
                : message.from;

            if (addresses == null)
                continue;

            foreach (Geary.RFC822.MailboxAddress address in addresses) {
                Participant participant_display = new Participant(address);

                int existing_index = participants.index_of(participant_display);
                if (existing_index < 0) {
                    participants.add(participant_display);

                    continue;
                }
            }
        }

        if (participants.size == 0) {
            return "";
        }

        if(participants.size == 1) {
            return participants[0].get_full_markup(this.user_accounts);
        }

        StringBuilder builder = new StringBuilder();
        bool first = true;
        foreach (Participant participant in participants) {
            if (!first) {
                builder.append(", ");
            }

            builder.append(participant.get_short_markup(this.user_accounts));
            first = false;
        }

        return builder.str;
    }
}

