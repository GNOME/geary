/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A Gtk.ListBoxRow child that displays a conversation in the list.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-list-item.ui")]
public class ConversationListItem : Gtk.Grid {

    private const string STARRED_CLASS = "geary-starred";
    private const string UNREAD_CLASS = "geary-unread";

    // Translators: This stands in place for the user's name in the
    // list of participants in a conversation.
    private const string ME = _("Me");

    private class ParticipantDisplay : Geary.BaseObject, Gee.Hashable<ParticipantDisplay> {

        public Geary.RFC822.MailboxAddress address;
        public bool is_unread;

        public ParticipantDisplay(Geary.RFC822.MailboxAddress address, bool is_unread) {
            this.address = address;
            this.is_unread = is_unread;
        }

        public string get_full_markup(Gee.List<Geary.RFC822.MailboxAddress> account_mailboxes) {
            return get_as_markup((address in account_mailboxes) ? ME : address.get_short_address());
        }

        public string get_short_markup(Gee.List<Geary.RFC822.MailboxAddress> account_mailboxes) {
            if (address in account_mailboxes)
                return get_as_markup(ME);

            string short_address = address.get_short_address().strip();

            if (", " in short_address) {
                // assume address is in Last, First format
                string[] tokens = short_address.split(", ", 2);
                short_address = tokens[1].strip();
                if (Geary.String.is_empty(short_address))
                    return get_full_markup(account_mailboxes);
            }

            // use first name as delimited by a space
            string[] tokens = short_address.split(" ", 2);
            if (tokens.length < 1)
                return get_full_markup(account_mailboxes);

            string first_name = tokens[0].strip();
            if (Geary.String.is_empty_or_whitespace(first_name))
                return get_full_markup(account_mailboxes);

            return get_as_markup(first_name);
        }

        private string get_as_markup(string participant) {
            return "%s%s%s".printf(
                is_unread ? "<b>" : "", Geary.HTML.escape_markup(participant), is_unread ? "</b>" : "");
        }

        public bool equal_to(ParticipantDisplay other) {
            return address.equal_to(other.address);
        }

        public uint hash() {
            return address.hash();
        }
    }


    [GtkChild]
    private Gtk.Button star_button;

    [GtkChild]
    private Gtk.Button unstar_button;

    [GtkChild]
    private Gtk.Label participants;

    [GtkChild]
    private Gtk.Label subject;

    [GtkChild]
    private Gtk.Label preview;

    [GtkChild]
    private Gtk.Label date;

    [GtkChild]
    private Gtk.Label count;

    private Geary.App.Conversation conversation;
    private Gee.List<Geary.RFC822.MailboxAddress> account_addresses;
    private bool use_to;
    private Configuration config;

    public ConversationListItem(Geary.App.Conversation conversation,
                                Gee.List<Geary.RFC822.MailboxAddress> account_addresses,
                                bool use_to,
                                Configuration config) {
        this.conversation = conversation;
        this.account_addresses = account_addresses;
        this.use_to = use_to;
        this.config = config;

        this.conversation.appended.connect(() => { update(); });
        this.conversation.trimmed.connect(() => { update(); });
        this.conversation.email_flags_changed.connect(() => { update(); });

        this.config.notify["clock-format"].connect(() => { update(); });
        this.config.notify["display-preview"].connect(() => { update(); });
        update();
    }

    private void update() {
        Gtk.StyleContext style = get_style_context();

        if (this.conversation.is_flagged()) {
            style.add_class(STARRED_CLASS);
            this.star_button.hide();
            this.unstar_button.show();
        } else {
            style.remove_class(STARRED_CLASS);
            this.star_button.show();
            this.unstar_button.hide();
        }

        if (this.conversation.is_unread()) {
            style.add_class(UNREAD_CLASS);
        } else {
            style.remove_class(UNREAD_CLASS);
        }

        string participants = get_participants_markup();
        this.participants.set_markup(participants);
        this.participants.set_tooltip_markup(participants);

        // Use the latest message in the conversation by sender's date
        // for extracting preview text for use here
        Geary.Email? preview_message = this.conversation.get_latest_recv_email(
            Geary.App.Conversation.Location.ANYWHERE
        );

        string subject_markup = this.conversation.is_unread() ? "<b>%s</b>" : "%s";
        subject_markup = Markup.printf_escaped(
            subject_markup,
            Geary.String.reduce_whitespace(EmailUtil.strip_subject_prefixes(preview_message))
        );
        this.subject.set_markup(subject_markup);
        if (preview_message.subject != null) {
            this.subject.set_tooltip_text(
                Geary.String.reduce_whitespace(preview_message.subject.to_string())
            );
        }

        string preview_text = "long long long long preview";
        if (this.config.display_preview) {
            // XXX load & format preview here
            // preview_text = XXXX;
            preview.set_text(preview_text);
            preview.show();
        } else {
            preview.hide();
        }

        // conversation list store sorts by date-received, so
        // display that instead of sender's Date:
        string date_text = "";
        string date_tooltip = "";
        Geary.Email? latest_message = this.conversation.get_latest_recv_email(
            Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER
        );
        if (latest_message != null && latest_message.properties != null) {
            date_text = Date.pretty_print(
                latest_message.properties.date_received, this.config.clock_format
            );
            date_tooltip = Date.pretty_print_verbose(
                latest_message.properties.date_received, this.config.clock_format
            );
        }
        this.date.set_text(date_text);
        this.date.set_tooltip_text(date_tooltip);

        uint count = this.conversation.get_count();
        this.count.set_text("%u".printf(count));
        if (count <= 1) {
            this.count.hide();
        }
    }

    private string get_participants_markup() {
        // Build chronological list of AuthorDisplay records, setting
        // to unread if any message by that author is unread
        Gee.ArrayList<ParticipantDisplay> list = new Gee.ArrayList<ParticipantDisplay>();
        foreach (Geary.Email message in conversation.get_emails(Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING)) {
            Geary.RFC822.MailboxAddresses? addresses = this.use_to ? message.to : message.from;
            if (addresses != null) {
                foreach (Geary.RFC822.MailboxAddress address in addresses) {
                    ParticipantDisplay participant_display = new ParticipantDisplay(address,
                                                                                    message.email_flags.is_unread());

                    // if not present, add in chronological order
                    int existing_index = list.index_of(participant_display);
                    if (existing_index < 0) {
                        list.add(participant_display);

                        continue;
                    }

                    // if present and this message is unread but the prior were read,
                    // this author is now unread
                    if (message.email_flags.is_unread() && !list[existing_index].is_unread)
                        list[existing_index].is_unread = true;
                }
            }
        }

        StringBuilder builder = new StringBuilder();
        if (list.size == 1) {
            // if only one participant, use full name
            builder.append(list[0].get_full_markup(this.account_addresses));
        } else {
            bool first = true;
            foreach (ParticipantDisplay participant in list) {
                if (!first)
                    builder.append(", ");

                builder.append(participant.get_short_markup(this.account_addresses));
                first = false;
            }
        }

        return builder.str;
    }

}
