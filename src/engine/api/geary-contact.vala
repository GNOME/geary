/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Contact : BaseObject {
    public string normalized_email { get; private set; }
    public string email { get; private set; }
    public string? real_name { get; private set; }
    public int highest_importance { get; set; }
    public ContactFlags? contact_flags { get; set; default = null; }
    
    public Contact(string email, string? real_name, int highest_importance,
        string? normalized_email = null, ContactFlags? contact_flags = null) {
        this.normalized_email = normalized_email ?? email.normalize().casefold();
        this.email = email;
        this.real_name = real_name;
        this.highest_importance = highest_importance;
        this.contact_flags = contact_flags;
    }
    
    public Contact.from_rfc822_address(RFC822.MailboxAddress address, int highest_importance) {
        this(address.address, address.name, highest_importance);
    }
    
    public RFC822.MailboxAddress get_rfc822_address() {
        return new RFC822.MailboxAddress(real_name, email);
    }
    
    public inline bool always_load_remote_images() {
        return contact_flags != null && contact_flags.always_load_remote_images();
    }
}
