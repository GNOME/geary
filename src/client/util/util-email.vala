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

public string get_participants(Geary.App.Conversation conversation, string account_owner_email,
    bool use_to, bool markup, string? foreground = null) {
    string normalized_account_owner_email = account_owner_email.normalize().casefold();
    
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
            if (markup && message.email_flags.is_unread() && !list[existing_index].is_unread)
                list[existing_index].is_unread = true;
        }
    }
    
    StringBuilder builder = new StringBuilder(markup ? @"<span foreground='$foreground'>" : "");
    if (list.size == 1) {
        // if only one participant, use full name
        builder.append(list[0].get_full_markup(normalized_account_owner_email));
    } else {
        bool first = true;
        foreach (ParticipantDisplay participant in list) {
            if (!first)
                builder.append(", ");
            
            builder.append(participant.get_short_markup(normalized_account_owner_email));
            first = false;
        }
    }
    if (markup)
        builder.append("</span>");
    
    return builder.str;
}

private class ParticipantDisplay : Geary.BaseObject, Gee.Hashable<ParticipantDisplay> {
    private const string ME = _("Me");
    
    public string key;
    public Geary.RFC822.MailboxAddress address;
    public bool is_unread;
    
    public ParticipantDisplay(Geary.RFC822.MailboxAddress address, bool is_unread) {
        key = address.as_key();
        this.address = address;
        this.is_unread = is_unread;
    }
    
    public string get_full_markup(string normalized_account_key) {
        return get_as_markup((key == normalized_account_key) ? ME : address.get_short_address());
    }
    
    public string get_short_markup(string normalized_account_key) {
        if (key == normalized_account_key)
            return get_as_markup(ME);
        
        string short_address = address.get_short_address().strip();
        
        if (", " in short_address) {
            // assume address is in Last, First format
            string[] tokens = short_address.split(", ", 2);
            short_address = tokens[1].strip();
            if (Geary.String.is_empty(short_address))
                return get_full_markup(normalized_account_key);
        }
        
        // use first name as delimited by a space
        string[] tokens = short_address.split(" ", 2);
        if (tokens.length < 1)
            return get_full_markup(normalized_account_key);
        
        string first_name = tokens[0].strip();
        if (Geary.String.is_empty_or_whitespace(first_name))
            return get_full_markup(normalized_account_key);
        
        return get_as_markup(first_name);
    }
    
    private string get_as_markup(string participant) {
        return "%s%s%s".printf(
            is_unread ? "<b>" : "", Geary.HTML.escape_markup(participant), is_unread ? "</b>" : "");
    }
    
    public bool equal_to(ParticipantDisplay other) {
        if (this == other)
            return true;
        
        return key == other.key;
    }
    
    public uint hash() {
        return key.hash();
    }
}

}

