/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public int compare_conversation_ascending(Geary.App.Conversation a, Geary.App.Conversation b) {
    Geary.Email? a_latest = a.get_latest_recv_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
    Geary.Email? b_latest = b.get_latest_recv_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
    
    if (a_latest == null)
        return (b_latest == null) ? 0 : -1;
    else if (b_latest == null)
        return 1;
    
    // use date-received so newly-arrived messages float to the top, even if they're send date
    // was earlier (think of mailing lists that batch up forwarded mail)
    return Geary.Email.compare_recv_date_ascending(a_latest, b_latest);
}

public int compare_conversation_descending(Geary.App.Conversation a, Geary.App.Conversation b) {
    return compare_conversation_ascending(b, a);
}

namespace EmailUtil {

public string strip_subject_prefixes(Geary.Email email) {
    string? cleaned = (email.subject != null) ? email.subject.strip_prefixes() : null;
    
    return !Geary.String.is_empty(cleaned) ? cleaned : _("(no subject)");
}

public string get_participants(Geary.App.Conversation conversation,
    Gee.List<Geary.RFC822.MailboxAddress> account_owner_emails, bool use_to, bool markup,
    string? foreground = null) {
    
    // Build chronological list of AuthorDisplay records, setting to unread if any message by
    // that author is unread
    Gee.ArrayList<ParticipantDisplay> list = new Gee.ArrayList<ParticipantDisplay>();
    foreach (Geary.Email message in conversation.get_emails(
        Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING)) {
        // only display if something to display
        Geary.RFC822.MailboxAddresses? addresses = use_to ? message.to : message.from;
        if (addresses == null || addresses.size < 1)
            continue;
        
        foreach (Geary.RFC822.MailboxAddress address in addresses) {
            ParticipantDisplay participant_display = new ParticipantDisplay(address,
                markup && message.email_flags.is_unread());

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
    
    StringBuilder builder = new StringBuilder(markup ? @"<span foreground='$foreground'>" : "");
    if (list.size == 1) {
        // if only one participant, use full name
        builder.append(list[0].get_full(account_owner_emails, markup));
    } else {
        bool first = true;
        foreach (ParticipantDisplay participant in list) {
            if (!first)
                builder.append(", ");
            
            builder.append(participant.get_short(account_owner_emails, markup));
            first = false;
        }
    }
    if (markup)
        builder.append("</span>");
    
    return builder.str;
}

private class ParticipantDisplay : Geary.BaseObject, Gee.Hashable<ParticipantDisplay> {
    private const string ME = _("Me");
    
    public Geary.RFC822.MailboxAddress address;
    public bool is_unread;
    
    public ParticipantDisplay(Geary.RFC822.MailboxAddress address, bool is_unread) {
        this.address = address;
        this.is_unread = is_unread;
    }
    
    public string get_full(Gee.List<Geary.RFC822.MailboxAddress> account_mailboxes, bool markup) {
        string name = (address in account_mailboxes) ? ME : address.get_short_address();
        return markup ? get_as_markup(name) : name;
    }
    
    public string get_short(Gee.List<Geary.RFC822.MailboxAddress> account_mailboxes, bool markup) {
        if (address in account_mailboxes)
            return markup ? get_as_markup(ME) : ME;
        
        string short_address = address.get_short_address().strip();
        
        if (", " in short_address) {
            // assume address is in Last, First format
            string[] tokens = short_address.split(", ", 2);
            short_address = tokens[1].strip();
            if (Geary.String.is_empty(short_address))
                return get_full(account_mailboxes, markup);
        }
        
        // use first name as delimited by a space
        string[] tokens = short_address.split(" ", 2);
        if (tokens.length < 1)
            return get_full(account_mailboxes, markup);
        
        string first_name = tokens[0].strip();
        if (Geary.String.is_empty_or_whitespace(first_name))
            return get_full(account_mailboxes, markup);
        
        return markup ? get_as_markup(first_name) : first_name;
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

}

