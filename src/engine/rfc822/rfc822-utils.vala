/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.RFC822.Utils {

// We use DEL to mark quote levels, since it's unlikely to be in email bodies, is a single byte
// in UTF-8, and is unmolested by GMime.FilterHTML.
public const char QUOTE_MARKER = '\x7f';

public GMime.FilterCharset create_utf8_filter_charset(string from_charset) {
    GMime.FilterCharset? filter_charset = new GMime.FilterCharset(from_charset, "UTF-8");
    if (filter_charset == null) {
        debug("Unknown charset %s; treating as UTF-8", from_charset);
        filter_charset = new GMime.FilterCharset("UTF-8", "UTF-8");
        assert(filter_charset != null);
    }
    return filter_charset;
}

public string create_subject_for_reply(Geary.Email email) {
    return (email.subject ?? new Geary.RFC822.Subject("")).create_reply().value;
}

public string create_subject_for_forward(Geary.Email email) {
    return (email.subject ?? new Geary.RFC822.Subject("")).create_forward().value;
}

// Removes address from the list of addresses.  If the list contains only the given address, the
// behavior depends on empty_ok: if true the list will be emptied, otherwise it will leave the
// address in the list once. Used to remove the sender's address from a list of addresses being
// created for the "reply to" recipients.
private void remove_address(Gee.List<Geary.RFC822.MailboxAddress> addresses,
    string address, bool empty_ok = false) {
    for (int i = 0; i < addresses.size; ++i) {
        if (addresses[i].address == address && (empty_ok || addresses.size > 1))
            addresses.remove_at(i--);
    }
}

public string create_to_addresses_for_reply(Geary.Email email,
    string? sender_address = null) {
    Gee.List<Geary.RFC822.MailboxAddress> new_to =
        new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
    
    // If we're replying to something we sent, send it to the same people we originally did.
    // Otherwise, we'll send to the reply-to address or the from address.
    if (email.to != null && !String.is_empty(sender_address) && email.from.contains(sender_address))
        new_to.add_all(email.to.get_all());
    else if (email.reply_to != null)
        new_to.add_all(email.reply_to.get_all());
    else if (email.from != null)
        new_to.add_all(email.from.get_all());
    
    // Exclude the current sender.  No need to receive the mail they're sending.
    if (!String.is_empty(sender_address))
        remove_address(new_to, sender_address);
    
    return new_to.size > 0 ? new Geary.RFC822.MailboxAddresses(new_to).to_rfc822_string() : "";
}

public string create_cc_addresses_for_reply_all(Geary.Email email,
    string? sender_address = null) {
    Gee.List<Geary.RFC822.MailboxAddress> new_cc = new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
    
    // If we're replying to something we received, also add other recipients.  Don't do this for
    // emails we sent, since everyone we sent it to is already covered in
    // create_to_addresses_for_reply().
    if (email.to != null && (String.is_empty(sender_address) ||
        !email.from.contains(sender_address)))
        new_cc.add_all(email.to.get_all());
    
    if (email.cc != null)
        new_cc.add_all(email.cc.get_all());
    
    // Again, exclude the current sender.
    if (!String.is_empty(sender_address))
        remove_address(new_cc, sender_address, true);
    
    return new_cc.size > 0 ? new Geary.RFC822.MailboxAddresses(new_cc).to_rfc822_string() : "";
}

public string reply_references(Geary.Email source) {
    // generate list for References
    Gee.ArrayList<RFC822.MessageID> list = new Gee.ArrayList<RFC822.MessageID>();
    
    // 1. Start with the source's References list
    if (source.references != null && source.references.list.size > 0)
        list.add_all(source.references.list);
    
    // 2. If there's an In-Reply-To Message-ID and it's not the last Message-ID on the 
    //    References list, append it
    if (source.in_reply_to != null && list.size > 0 && !list.last().equals(source.in_reply_to))
        list.add(source.in_reply_to);
    
    // 3. Append the source's Message-ID, if available.
    if (source.message_id != null)
        list.add(source.message_id);
    
    string[] strings = new string[list.size];
    for(int i = 0; i < list.size; ++i)
        strings[i] = list[i].value;
    
    return (list.size > 0) ? string.joinv(" ", strings) : "";
}

public string email_addresses_for_reply(Geary.RFC822.MailboxAddresses? addresses,
    bool html_format) {
    
    if (addresses == null)
        return "";
    
    return html_format ? HTML.escape_markup(addresses.to_string()) : addresses.to_string();
}


/**
 * Returns a quoted text string needed for a reply.
 *
 * If there's no message body in the supplied email, this function will
 * return the empty string.
 * 
 * If html_format is true, the message will be quoted in HTML format.
 * Otherwise it will be in plain text.
 */
public string quote_email_for_reply(Geary.Email email, bool html_format) {
    if (email.body == null)
        return "";
    
    string quoted = "<br /><br />";
    
    /// Format for the datetime that a message being replied to was received
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    string DATE_FORMAT = _("%a, %b %-e, %Y at %-l:%M %p");

    if (email.date != null && email.from != null) {
        /// The quoted header for a message being replied to.
        /// %1$s will be substituted for the date, and %2$s will be substituted for
        /// the original sender.
        string QUOTED_LABEL = _("On %1$s, %2$s wrote:");
        quoted += QUOTED_LABEL.printf(email.date.value.format(DATE_FORMAT),
                                      email_addresses_for_reply(email.from, html_format));

    } else if (email.from != null) {
        /// The quoted header for a message being replied to (in case the date is not known).
        /// %s will be replaced by the original sender.
        string QUOTED_LABEL = _("%s wrote:");
        quoted += QUOTED_LABEL.printf(email_addresses_for_reply(email.from, html_format));

    } else if (email.date != null) {
        /// The quoted header for a message being replied to (in case the sender is not known).
        /// %s will be replaced by the original date
        string QUOTED_LABEL = _("On %s:");
        quoted += QUOTED_LABEL.printf(email.date.value.format(DATE_FORMAT));
    }
    
    quoted += "<br />";
    
    if (email.body != null)
        quoted += "\n" + quote_body(email, true, html_format);
    
    return quoted;
}

/**
 * Returns a quoted text string needed for a forward.
 *
 * If there's no message body in the supplied email, this function will
 * return the empty string.
 *
 * If html_format is true, the message will be quoted in HTML format.
 * Otherwise it will be in plain text.
 */
public string quote_email_for_forward(Geary.Email email, bool html_format) {
    if (email.body == null)
        return "";
    
    string quoted = "\n\n";
    
    quoted += _("---------- Forwarded message ----------");
    quoted += "\n\n";
    string from_line = email_addresses_for_reply(email.from, html_format);
    if (!String.is_empty_or_whitespace(from_line))
        quoted += _("From: %s\n").printf(from_line);
    quoted += _("Subject: %s\n").printf(email.subject != null ? email.subject.to_string() : "");
    quoted += _("Date: %s\n").printf(email.date != null ? email.date.to_string() : "");
    string to_line = email_addresses_for_reply(email.to, html_format);
    if (!String.is_empty_or_whitespace(to_line))
        quoted += _("To: %s\n").printf(to_line);
    quoted += "\n";  // A blank line between headers and body
    
    quoted = quoted.replace("\n", "<br />");
    
    if (email.body != null)
        quoted += quote_body(email, false, html_format);
    
    return quoted;
}

private string quote_body(Geary.Email email, bool use_quotes, bool html_format) {
    string body_text = "";
    
    try {
        body_text = email.get_message().get_body(html_format);
    } catch (Error error) {
        debug("Could not get message text. %s", error.message);
    }
    
    // Wrap the whole thing in a blockquote.
    if (use_quotes)
        body_text = "<blockquote type=\"cite\">%s</blockquote>".printf(body_text);
    
    return body_text;
}

public bool comp_char_arr_slice(char[] array, uint start, string comp) {
    for (int i = 0; i < comp.length; i++) {
        if (array[start + i] != comp[i])
            return false;
    }
    
    return true;
}

}

