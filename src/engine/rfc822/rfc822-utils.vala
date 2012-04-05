/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.RFC822.Utils {

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
    
    string quoted = "";
    
    if (email.date != null)
        quoted += _("On %s, ").printf(email.date.value.format(_("%a, %b %-e, %Y at %-l:%M %p")));
    
    if (email.from != null)
        quoted += _("%s wrote:").printf(email.from.to_string());
    
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
    
    string quoted = "";
    
    quoted += _("---------- Forwarded message ----------");
    quoted += "\n\n";
    quoted += _("From: %s\n").printf(email.from != null ? email.from.to_string() : "");
    quoted += _("Subject %s\n").printf(email.subject != null ? email.subject.to_string() : "");
    quoted += _("Date: %s\n").printf(email.date != null ? email.date.to_string() : "");
    quoted += _("To: %s\n").printf(email.to != null ? email.to.to_string() : "");
    
    if (html_format)
        quoted = quoted.replace("\n", "<br />");
    
    if (email.body != null)
        quoted += "\n" + quote_body(email, false, html_format);
    
    return quoted;
}

private string text_from_message(Geary.Email email, bool html_format) throws Error {
    if (html_format) {
        return email.get_message().get_first_mime_part_of_content_type("text/html").to_utf8();
    } else {
        return email.get_message().get_first_mime_part_of_content_type("text/plain").to_utf8();
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
            body_text = "<blockquote>%s</blockquote>".printf(body_text);
        
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

