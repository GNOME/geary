/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageBuffer : Gtk.TextBuffer {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT;
    
    public MessageBuffer() {
    }
    
    public void clear() {
        set_text("");
    }
    
    // Would very much like to use Pango markup to format the text, however, it's not supported
    // in Gtk.TextBuffer/Gtk.TextView by default, meaning the implementor has to devise their own
    // markup language, parse the buffer, and so on. See:
    // https://bugzilla.gnome.org/show_bug.cgi?id=59390
    public void display_email(Geary.Email email) throws Error {
        StringBuilder builder = new StringBuilder();
        
        // From:
        if (email.from != null && email.from.size > 0)
            builder.append_printf(_("From: %s\n"), email.from.to_string());
        else if (email.sender != null && email.sender.size > 0)
            builder.append_printf(_("Sender: %s\n"), email.sender.to_string());
        
        // To:
        if (email.to != null && email.to.size > 0)
            builder.append_printf(_("To: %s\n"), email.to.to_string());
        
        if (email.cc != null && email.cc.size > 0)
            builder.append_printf(_("Cc: %s\n"), email.cc.to_string());
        
        if (email.bcc != null && email.bcc.size > 0)
            builder.append_printf(_("Bcc: %s"), email.bcc.to_string());
        
        // Subject:
        if (email.subject != null)
            builder.append_printf(_("Subject: %s\n"), email.subject.value);
        
        // Message body
        Geary.Memory.AbstractBuffer buffer = email.get_message().get_first_mime_part_of_content_type(
            "text/plain");
        builder.append("\n");
        builder.append(buffer.to_utf8());
        
        set_text(builder.str);
    }
}

