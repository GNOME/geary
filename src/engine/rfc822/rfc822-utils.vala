/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.RFC822.Utils {

/**
 * Returns a quoted text string, needed for a reply or forward.
 *
 * If there's no message body in the supplied email, this function will
 * return the empty string.
 *
 * TODO: Support HTML as an option.
 */
public string quote_email(Geary.Email email) {
    if (email.body == null)
        return "";
    
    string quoted = "";
    
    if (email.date != null)
        quoted += _("On %s, ").printf(email.date.to_string());
    
    if (email.from != null)
        quoted += _("%s wrote:").printf(email.from.to_string());
    
    if (email.body != null) {
        quoted += "\n\n";
        try {
            string[] lines = email.get_message().get_first_mime_part_of_content_type("text/plain")
                .to_utf8().split("\n");
            for (int i = 0; i < lines.length; i++) {
                quoted += "> " + lines[i];
            }
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
            
            return ""; // empty string on no body
        }
    }
    
    return quoted;
}

}

