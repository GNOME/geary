/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.RFC822.Utils {

// We use DEL to mark quote levels, since it's unlikely to be in email bodies, is a single byte
// in UTF-8, and is unmolested by GMime.FilterHTML.
public const char QUOTE_MARKER = '\x7f';

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
    
    string quoted = html_format ? "<br /><br />" : "\n\n";
    
    if (email.date != null) {
        /// The datetime that a message being replied to was received
        string DATE_LABEL = _("On %s, ");
        /// Format for the datetime that a message being replied to was received
        /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
        string DATE_FORMAT = _("%a, %b %-e, %Y at %-l:%M %p");
        quoted += DATE_LABEL.printf(email.date.value.format(DATE_FORMAT));
    }
    
    if (email.from != null)
        quoted += _("%s wrote:").printf(email_addresses_for_reply(email.from, html_format));
    
    if (html_format)
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
    
    string quoted = html_format ? "<br /><br />" : "\n\n";
    
    quoted += _("---------- Forwarded message ----------");
    quoted += "\n\n";
    string from_line = email_addresses_for_reply(email.from, html_format);
    if (!String.is_empty_or_whitespace(from_line))
        quoted += _("From: %s\n").printf(from_line);
    // TODO: Doing it this way because string change happened after string freeze and "Subject" is
    // available but not "Subject: %s"
    quoted += _("Subject:") + "%s\n".printf(email.subject != null ? email.subject.to_string() : "");
    quoted += _("Date: %s\n").printf(email.date != null ? email.date.to_string() : "");
    string to_line = email_addresses_for_reply(email.to, html_format);
    if (!String.is_empty_or_whitespace(to_line))
        quoted += _("To: %s\n").printf(to_line);
    
    // only add extra blank line if body exists and first line of *plain text* body is not a blank
    // line (this test won't work with HTML, but formatting applies to it too)
    if (email.body != null) {
        try {
            Memory.StringBuffer stringb = new Memory.StringBuffer(text_from_message(email, false));
            DataInputStream dins = new DataInputStream(stringb.get_input_stream());
            dins.set_newline_type(DataStreamNewlineType.ANY);
            
            string line = dins.read_line();
            if (!String.is_empty_or_whitespace(line))
                quoted += "\n";
        } catch (Error err) {
            debug("Error attempting to inspect first line of body buffer: %s", err.message);
            
            // add blank line; better to have too many than not enough
            quoted += "\n";
        }
    }
    
    if (html_format)
        quoted = quoted.replace("\n", "<br />");
    
    if (email.body != null)
        quoted += quote_body(email, false, html_format);
    
    return quoted;
}

private string text_from_message(Geary.Email email, bool html_format) throws Error {
    if (html_format) {
        return email.get_message().get_first_mime_part_of_content_type("text/html").to_string();
    } else {
        return email.get_message().get_first_mime_part_of_content_type("text/plain").to_string();
    }
}

private string quote_body(Geary.Email email, bool use_quotes, bool html_format) {
    string body_text = "";
    
    if (html_format) {
        try {
            body_text = text_from_message(email, true);
        } catch (Error err) {
            try {
                body_text = text_from_message(email, false).replace("\n", "<br />");
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }
        
        // Wrap the whole thing in a blockquote.
        if (use_quotes)
            body_text = "<blockquote type=\"cite\">%s</blockquote>".printf(body_text);
        
        return body_text;
    } else {
        // Get message text.  First we'll try text, but if that fails we'll
        // resort to stripping tags out of the HTML section.
        try {
            body_text = text_from_message(email, false);
        } catch (Error err) {
            try {
                body_text = Geary.HTML.remove_html_tags(text_from_message(email, false));
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }
        
        // Add the quoted message > symbols.
        string ret = "";
        string[] lines = body_text.split("\n");
        for (int i = 0; i < lines.length; i++) {
            if (use_quotes)
                ret += "> ";
            
            ret += lines[i];
        }
        
        return ret;
    }
}

}

