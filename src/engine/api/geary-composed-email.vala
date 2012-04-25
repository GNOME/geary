/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.ComposedEmail : Object {
    public const Geary.Email.Field REQUIRED_REPLY_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.REFERENCES
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.PROPERTIES;
    
    public DateTime date { get; set; }
    public RFC822.MailboxAddresses from { get; set; }
    public RFC822.MailboxAddresses? to { get; set; default = null; }
    public RFC822.MailboxAddresses? cc { get; set; default = null; }
    public RFC822.MailboxAddresses? bcc { get; set; default = null; }
    public RFC822.MessageID? in_reply_to { get; set; default = null; }
    public Geary.Email? reply_to_email { get; set; default = null; }
    public RFC822.MessageIDList? references { get; set; default = null; }
    public RFC822.Subject? subject { get; set; default = null; }
    public RFC822.Text? body_text { get; set; default = null; }
    public RFC822.Text? body_html { get; set; default = null; }
    public string? mailer { get; set; default = null; }
    
    public ComposedEmail(DateTime date, RFC822.MailboxAddresses from, 
        RFC822.MailboxAddresses? to = null, RFC822.MailboxAddresses? cc = null,
        RFC822.MailboxAddresses? bcc = null, RFC822.Subject? subject = null) {
        this.date = date;
        this.from = from;
        this.to = to;
        this.cc = cc;
        this.bcc = bcc;
        this.subject = subject;
    }
    
    public ComposedEmail.as_reply(DateTime date, RFC822.MailboxAddresses from, Geary.Email source) {
        this (date, from);
        assert(source.fields.fulfills(REQUIRED_REPLY_FIELDS));
        
        string? sender_address = (from.size > 0 ? from.get_all().first().address : null);
        to = create_to_addresses_for_reply(source, sender_address);
        subject = create_subject_for_reply(source);
        set_reply_references(source);
        
        body_text = new RFC822.Text(new Geary.Memory.StringBuffer("\n\n" +
            Geary.RFC822.Utils.quote_email_for_reply(source, false)));
        body_html = new RFC822.Text(new Geary.Memory.StringBuffer("\n\n" +
            Geary.RFC822.Utils.quote_email_for_reply(source, true)));
    }
    
    public ComposedEmail.as_reply_all(DateTime date, RFC822.MailboxAddresses from, Geary.Email source) {
        this (date, from);
        assert(source.fields.fulfills(REQUIRED_REPLY_FIELDS));
        
        string? sender_address = (from.size > 0 ? from.get_all().first().address : null);
        to = create_to_addresses_for_reply(source, sender_address);
        cc = create_cc_addresses_for_reply_all(source, sender_address);
        subject = create_subject_for_reply(source);
        set_reply_references(source);
        
        body_text = new RFC822.Text(new Geary.Memory.StringBuffer("\n\n" +
            Geary.RFC822.Utils.quote_email_for_reply(source, false)));
        body_html = new RFC822.Text(new Geary.Memory.StringBuffer("\n\n" +
            Geary.RFC822.Utils.quote_email_for_reply(source, true)));
    }
    
    public ComposedEmail.as_forward(DateTime date, RFC822.MailboxAddresses from, Geary.Email source) {
        this (date, from);
        
        subject = create_subject_for_forward(source);
        
        body_text = new RFC822.Text(new Geary.Memory.StringBuffer("\n\n" +
            Geary.RFC822.Utils.quote_email_for_forward(source, false)));
        body_html = new RFC822.Text(new Geary.Memory.StringBuffer("\n\n" +
            Geary.RFC822.Utils.quote_email_for_forward(source, true)));
    }

    public ComposedEmail.from_mailto(string mailto, RFC822.MailboxAddresses default_from) {
        DateTime date = new DateTime.now_local();
        RFC822.MailboxAddresses from = default_from; 
        RFC822.MailboxAddresses? to = null;
        RFC822.MailboxAddresses? cc = null;
        RFC822.MailboxAddresses? bcc = null;
        RFC822.Subject? subject = null;

        if (mailto.length > "mailto:".length) {
            // Parse the mailto link.
            string[] parts = mailto.substring("mailto:".length).split("?", 2);
            string email = Uri.unescape_string(parts[0]);
            string[] params = parts.length == 2 ? parts[1].split("&") : new string[0];
            Gee.HashMap<string, string> headers = new Gee.HashMap<string, string>();
            foreach (string param in params) {
                string[] param_parts = param.split("=", 2);
                if (param_parts.length == 2) {
                    headers.set(Uri.unescape_string(param_parts[0]).down(),
                        Uri.unescape_string(param_parts[1]));
                }
            }

            // Assemble the headers.
            if (headers.has_key("from")) {
                from = new RFC822.MailboxAddresses.from_rfc822_string(headers.get("from"));
            }

            if (email.length > 0 && headers.has_key("to")) {
                to = new RFC822.MailboxAddresses.from_rfc822_string("%s,%s".printf(email, headers.get("to")));
            } else if (email.length > 0) {
                to = new RFC822.MailboxAddresses.from_rfc822_string(email);
            } else if (headers.has_key("to")) {
                to = new RFC822.MailboxAddresses.from_rfc822_string(headers.get("to"));
            }

            if (headers.has_key("cc")) {
                cc = new RFC822.MailboxAddresses.from_rfc822_string(headers.get("cc"));
            }

            if (headers.has_key("bcc")) {
                bcc = new RFC822.MailboxAddresses.from_rfc822_string(headers.get("bcc"));
            }

            if (headers.has_key("subject")) {
                subject = new RFC822.Subject(headers.get("subject"));
            }
        }

        // And construct!
        this(date, from, to, cc, bcc, subject);
    }

    private void set_reply_references(Geary.Email source) {
        in_reply_to = source.message_id;
        reply_to_email = source;
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
        
        if (list.size > 0)
            references = new RFC822.MessageIDList.from_list(list);
        else
            references = null;
    }
    
    private Geary.RFC822.Subject create_subject_for_reply(Geary.Email email) {
        return (email.subject ?? new Geary.RFC822.Subject("")).create_reply();
    }
    
    private Geary.RFC822.Subject create_subject_for_forward(Geary.Email email) {
        return (email.subject ?? new Geary.RFC822.Subject("")).create_forward();
    }
    
    // Removes address from the list of addresses.  If the list contains only the given address, the
    // behavior depends on empty_ok: if true the list will be emptied, otherwise it will leave the
    // address in the list once. Used to remove the sender's address from a list of addresses being
    // created for the "reply to" recipients.
    private static void remove_address(Gee.List<Geary.RFC822.MailboxAddress> addresses,
        string address, bool empty_ok = false) {
        for (int i = 0; i < addresses.size; ++i) {
            if (addresses[i].address == address && (empty_ok || addresses.size > 1))
                addresses.remove_at(i--);
        }
    }
    
    private Geary.RFC822.MailboxAddresses? create_to_addresses_for_reply(Geary.Email email,
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
        
        return new_to.size > 0 ? new Geary.RFC822.MailboxAddresses(new_to) : null;
    }
    
    private Geary.RFC822.MailboxAddresses? create_cc_addresses_for_reply_all(Geary.Email email,
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
        
        return new_cc.size > 0 ? new Geary.RFC822.MailboxAddresses(new_cc) : null;
    }
}

