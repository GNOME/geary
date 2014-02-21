/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.MessageAddresses : BaseObject {
    // Read-only view.
    public Gee.Collection<Contact> contacts { get; private set; }
    
    private RFC822.MailboxAddresses? sender_addresses;
    private RFC822.MailboxAddresses? from_addresses;
    private RFC822.MailboxAddresses? to_addresses;
    private RFC822.MailboxAddresses? cc_addresses;
    private RFC822.MailboxAddresses? bcc_addresses;
    
    private int from_importance;
    private int to_importance;
    private int cc_importance;
    
    private MessageAddresses(string account_owner_email, RFC822.MailboxAddresses? sender_addresses,
        RFC822.MailboxAddresses? from_addresses, RFC822.MailboxAddresses? to_addresses,
        RFC822.MailboxAddresses? cc_addresses, RFC822.MailboxAddresses? bcc_addresses) {
        this.sender_addresses = sender_addresses;
        this.from_addresses = from_addresses;
        this.to_addresses = to_addresses;
        this.cc_addresses = cc_addresses;
        this.bcc_addresses = bcc_addresses;
        
        calculate_importance(account_owner_email);
        contacts = build_contacts();
   }
    
    private MessageAddresses.from_strings(string account_owner_email, string? sender_field,
        string? from_field, string? to_field, string? cc_field, string? bcc_field) {
        this(account_owner_email, get_addresses_from_string(sender_field),
            get_addresses_from_string(from_field), get_addresses_from_string(to_field),
            get_addresses_from_string(cc_field), get_addresses_from_string(bcc_field));
    }
    
    public MessageAddresses.from_email(string account_owner_email, Geary.Email email) {
        this(account_owner_email, email.sender, email.from, email.to, email.cc, email.bcc);
    }
    
    public MessageAddresses.from_row(string account_owner_email, MessageRow row) {
        this.from_strings(account_owner_email, row.sender, row.from, row.to, row.cc, row.bcc);
    }
    
    public MessageAddresses.from_result(string account_owner_email, Db.Result result) {
        this.from_strings(account_owner_email, get_string_or_null(result, "sender"),
            get_string_or_null(result, "from_field"), get_string_or_null(result, "to_field"),
            get_string_or_null(result, "cc"), get_string_or_null(result, "bcc"));
    }
    
    private static string? get_string_or_null(Db.Result result, string column) {
        try {
            return result.string_for(column);
        } catch (Geary.DatabaseError err) {
            debug("Error fetching addresses from message row: %s", err.message);
            return null;
        }
    }
    
    private static RFC822.MailboxAddresses? get_addresses_from_string(string? field) {
        return field == null ? null : new RFC822.MailboxAddresses.from_rfc822_string(field);
    }
    
    private void calculate_importance(string account_owner_email) {
        // "Sender" is different than "from", but we give it the same importance.
        bool account_owner_in_from =
            (sender_addresses != null && sender_addresses.contains_normalized(account_owner_email)) ||
            (from_addresses != null && from_addresses.contains_normalized(account_owner_email));
        bool account_owner_in_to = to_addresses != null &&
            to_addresses.contains_normalized(account_owner_email);
        
        // If the account owner's address does not appear in any of these fields, we assume they
        // were BCC'd.
        bool account_owner_in_cc =
            (cc_addresses != null && cc_addresses.contains_normalized(account_owner_email)) ||
            (bcc_addresses != null && bcc_addresses.contains_normalized(account_owner_email)) ||
            !(account_owner_in_from || account_owner_in_to);
        
        from_importance = -1;
        to_importance = -1;
        cc_importance = -1;
        
        if (account_owner_in_from) {
            from_importance = int.max(from_importance, ContactImportance.FROM_FROM);
            to_importance = int.max(to_importance, ContactImportance.FROM_TO);
            cc_importance = int.max(cc_importance, ContactImportance.FROM_CC);
        }
        
        if (account_owner_in_to) {
            from_importance = int.max(from_importance, ContactImportance.TO_FROM);
            to_importance = int.max(to_importance, ContactImportance.TO_TO);
            cc_importance = int.max(cc_importance, ContactImportance.TO_CC);
        }
        
        if (account_owner_in_cc) {
            from_importance = int.max(from_importance, ContactImportance.CC_FROM);
            to_importance = int.max(to_importance, ContactImportance.CC_TO);
            cc_importance = int.max(cc_importance, ContactImportance.CC_CC);
        }
    }
    
    private Gee.Collection<Contact> build_contacts() {
        Gee.Map<string, Contact> contacts_map = new Gee.HashMap<string, Contact>();
        
        add_contacts(contacts_map, sender_addresses, from_importance);
        add_contacts(contacts_map, from_addresses, from_importance);
        add_contacts(contacts_map, to_addresses, to_importance);
        add_contacts(contacts_map, cc_addresses, cc_importance);
        add_contacts(contacts_map, bcc_addresses, cc_importance);
        
        return contacts_map.values;
    }
    
    private void add_contacts(Gee.Map<string, Contact> contacts_map, RFC822.MailboxAddresses? addresses,
        int importance) {
        if (addresses == null)
            return;
        
        foreach (RFC822.MailboxAddress address in addresses)
            add_contact(contacts_map, address, importance);
    }
    
    private void add_contact(Gee.Map<string, Contact> contacts_map, RFC822.MailboxAddress address,
        int importance) {
        if (!address.is_valid())
            return;
        
        Contact contact = new Contact.from_rfc822_address(address, importance);
        Contact? old_contact = contacts_map[contact.normalized_email];
        if (old_contact == null || old_contact.highest_importance < contact.highest_importance)
            contacts_map[contact.normalized_email] = contact;
    }
}
