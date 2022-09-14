/*
 * Copyright © 2022 John Renner <john@jrenner.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

internal class ConversationList.Participant : Geary.BaseObject, Gee.Hashable<Participant> {
    private const string ME = "Me";
    public Geary.RFC822.MailboxAddress address;

    public Participant(Geary.RFC822.MailboxAddress address) {
        this.address = address;
    }

    public string get_full_markup(Gee.List<Geary.RFC822.MailboxAddress> account_mailboxes) {
        return get_as_markup((address in account_mailboxes) ? ME : address.to_short_display());
    }

    public string get_short_markup(Gee.List<Geary.RFC822.MailboxAddress> account_mailboxes) {
        if (address in account_mailboxes)
            return get_as_markup(ME);

        if (address.is_spoofed()) {
            return get_full_markup(account_mailboxes);
        }

        string short_address = Markup.escape_text(address.to_short_display());

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
        string markup = Geary.HTML.escape_markup(participant);

        if (this.address.is_spoofed()) {
            markup = "<s>%s</s>".printf(markup);
        }

        return markup;
    }

    public bool equal_to(Participant other) {
        return address.equal_to(other.address)
            && address.name == other.address.name;
    }

    public uint hash() {
        return address.hash();
    }
}
