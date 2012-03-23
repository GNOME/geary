/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

[DBus (name = "org.yorba.Geary.Email", timeout = 120000)]
public class Geary.DBus.Email : Object {
    public static const string INTERFACE_NAME = "org.yorba.Geary.Email";
    
    public string to { get; private set; }
    public string from { get; private set; }
    public string cc { get; private set; }
    public string subject { get; private set; }
    public int64 date { get; private set; }
    public bool read { get; private set; }
    
    private Geary.Folder folder;
    private Geary.Email email;
    
    public Email(Geary.Folder f, Geary.Email e) {
        folder = f;
        email = e;
        
        to =  email.to != null ? email.to.to_string() : "";
        from = email.from != null ? email.from.to_string() : "";
        cc = email.cc != null ? email.cc.to_string() : "";
        subject = email.subject != null ? email.subject.to_string() : "";
        date = email.date != null ? email.date.as_time_t : 0;
        read = email.properties != null ? email.properties.email_flags.contains(EmailFlags.UNREAD)
            : true;
    }
    
    public async string get_body() throws IOError {
        string body_text = "";
        Geary.Email full_email;
        
        try {
            full_email = yield folder.fetch_email_async(email.id, Geary.Email.Field.ALL,
                Geary.Folder.ListFlags.NONE);
        } catch (Error err) {
            warning("Could not load email: %s", err.message);
            return "";
        }
        
        try {
            body_text = full_email.get_message().get_first_mime_part_of_content_type("text/html").
                to_utf8();
        } catch (Error err) {
            try {
                body_text = full_email.get_message().get_first_mime_part_of_content_type("text/plain").
                    to_utf8();
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }
        
        return body_text;
    }
    
    public async void remove() throws IOError {
        try {
            yield folder.remove_single_email_async(email.id);
        } catch (Error e) {
            if (e is IOError)
                throw (IOError) e;
            else
                warning("Unexpected error removing email: %s", e.message);
        }
    }
}

