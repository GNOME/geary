/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageRow : Geary.Sqlite.Row {
    public int64 id { get; set; default = INVALID_ID; }
    public Geary.Email.Field fields { get; set; default = Geary.Email.Field.NONE; }
    
    public string? date { get; set; }
    public time_t date_time_t { get; set; default = -1; }
    
    public string? from { get; set; }
    public string? sender { get; set; }
    public string? reply_to { get; set; }
    
    public string? to { get; set; }
    public string? cc { get; set; }
    public string? bcc { get; set; }
    
    public string? message_id { get; set; }
    public string? in_reply_to { get; set; }
    public string? references { get; set; }
    
    public string? subject { get; set; }
    
    public string? header { get; set; }
    
    public string? body { get; set; }
    
    public MessageRow(Table table) {
        base (table);
    }
    
    public MessageRow.from_email(MessageTable table, Geary.Email email) {
        base (table);
        
        set_from_email(email.fields, email);
    }
    
    public MessageRow.from_query_result(Table table, Geary.Email.Field requested_fields,
        SQLHeavy.QueryResult result) throws Error {
        base (table);
        
        id = fetch_int64_for(result, MessageTable.Column.ID);
        
        // the available fields are an intersection of what's available in the database and
        // what was requested
        fields = requested_fields & fetch_int_for(result, MessageTable.Column.FIELDS);
        
        if ((fields & Geary.Email.Field.DATE) != 0) {
            date = fetch_string_for(result, MessageTable.Column.DATE_FIELD);
            date_time_t = (time_t) fetch_int64_for(result, MessageTable.Column.DATE_TIME_T);
        }
        
        if ((fields & Geary.Email.Field.ORIGINATORS) != 0) {
            from = fetch_string_for(result, MessageTable.Column.FROM_FIELD);
            sender = fetch_string_for(result, MessageTable.Column.SENDER);
            reply_to = fetch_string_for(result, MessageTable.Column.REPLY_TO);
        }
        
        if ((fields & Geary.Email.Field.RECEIVERS) != 0) {
            to = fetch_string_for(result, MessageTable.Column.TO_FIELD);
            cc = fetch_string_for(result, MessageTable.Column.CC);
            bcc = fetch_string_for(result, MessageTable.Column.BCC);
        }
        
        if ((fields & Geary.Email.Field.REFERENCES) != 0) {
            message_id = fetch_string_for(result, MessageTable.Column.MESSAGE_ID);
            in_reply_to = fetch_string_for(result, MessageTable.Column.IN_REPLY_TO);
            references = fetch_string_for(result, MessageTable.Column.REFERENCES);
        }
        
        if ((fields & Geary.Email.Field.SUBJECT) != 0)
            subject = fetch_string_for(result, MessageTable.Column.SUBJECT);
        
        if ((fields & Geary.Email.Field.HEADER) != 0)
            header = fetch_string_for(result, MessageTable.Column.HEADER);
        
        if ((fields & Geary.Email.Field.BODY) != 0)
            body = fetch_string_for(result, MessageTable.Column.BODY);
    }
    
    public Geary.Email to_email(Geary.EmailLocation location, Geary.EmailIdentifier id) throws Error {
        Geary.Email email = new Geary.Email(location, id);
        
        if (((fields & Geary.Email.Field.DATE) != 0) && (date != null))
            email.set_send_date(new RFC822.Date(date));
        
        if ((fields & Geary.Email.Field.ORIGINATORS) != 0) {
            email.set_originators(unflatten_addresses(from), unflatten_addresses(sender),
                unflatten_addresses(reply_to));
        }
        
        if ((fields & Geary.Email.Field.RECEIVERS) != 0) {
            email.set_receivers(unflatten_addresses(to), unflatten_addresses(cc),
                unflatten_addresses(bcc));
        }
        
        if ((fields & Geary.Email.Field.REFERENCES) != 0) {
            email.set_full_references(
                (message_id != null) ? new RFC822.MessageID(message_id) : null,
                (in_reply_to != null) ? new RFC822.MessageID(in_reply_to) : null,
                (references != null) ? new RFC822.MessageIDList(references) : null);
        }
        
        if (((fields & Geary.Email.Field.SUBJECT) != 0) && (subject != null))
            email.set_message_subject(new RFC822.Subject(subject));
        
        if (((fields & Geary.Email.Field.HEADER) != 0) && (header != null))
            email.set_message_header(new RFC822.Header(new Geary.Memory.StringBuffer(header)));
        
        if (((fields & Geary.Email.Field.BODY) != 0) && (body != null))
            email.set_message_body(new RFC822.Text(new Geary.Memory.StringBuffer(body)));
        
        return email;
    }
    
    public void merge_from_network(Geary.Email email) {
        foreach (Geary.Email.Field field in Geary.Email.Field.all()) {
            if ((email.fields & field) != 0)
                set_from_email(field, email);
            else
                unset_fields(field);
        }
    }
    
    private string? flatten_addresses(RFC822.MailboxAddresses? addrs) {
        if (addrs == null)
            return null;
        
        switch (addrs.size) {
            case 0:
                return null;
            
            case 1:
                return addrs[0].to_rfc822_string();
            
            default:
                StringBuilder builder = new StringBuilder();
                foreach (RFC822.MailboxAddress addr in addrs) {
                    if (!String.is_empty(builder.str))
                        builder.append(", ");
                    
                    builder.append(addr.to_rfc822_string());
                }
                
                return builder.str;
        }
    }
    
    private RFC822.MailboxAddresses? unflatten_addresses(string? str) {
        return String.is_empty(str) ? null : new RFC822.MailboxAddresses.from_rfc822_string(str);
    }
    
    private void set_from_email(Geary.Email.Field fields, Geary.Email email) {
        // Although the fields bitmask might indicate various fields are set, they may still be
        // null if empty
        
        if ((fields & Geary.Email.Field.DATE) != 0) {
            date = (email.date != null) ? email.date.original : null;
            date_time_t = (email.date != null) ? email.date.as_time_t : -1;
            
            this.fields = this.fields.set(Geary.Email.Field.DATE);
        }
        
        if ((fields & Geary.Email.Field.ORIGINATORS) != 0) {
            from = flatten_addresses(email.from);
            sender = flatten_addresses(email.sender);
            reply_to = flatten_addresses(email.reply_to);
            
            this.fields = this.fields.set(Geary.Email.Field.ORIGINATORS);
        }
        
        if ((fields & Geary.Email.Field.RECEIVERS) != 0) {
            to = flatten_addresses(email.to);
            cc = flatten_addresses(email.cc);
            bcc = flatten_addresses(email.bcc);
            
            this.fields = this.fields.set(Geary.Email.Field.RECEIVERS);
        }
        
        if ((fields & Geary.Email.Field.REFERENCES) != 0) {
            message_id = (email.message_id != null) ? email.message_id.value : null;
            in_reply_to = (email.in_reply_to != null) ? email.in_reply_to.value : null;
            references = (email.references != null) ? email.references.value : null;
            
            this.fields = this.fields.set(Geary.Email.Field.REFERENCES);
        }
        
        if ((fields & Geary.Email.Field.SUBJECT) != 0) {
            subject = (email.subject != null) ? email.subject.value : null;
            
            this.fields = this.fields.set(Geary.Email.Field.SUBJECT);
        }
        
        if ((fields & Geary.Email.Field.HEADER) != 0) {
            header = (email.header != null) ? email.header.buffer.to_utf8() : null;
            
            this.fields = this.fields.set(Geary.Email.Field.HEADER);
        }
        
        if ((fields & Geary.Email.Field.BODY) != 0) {
            body = (email.body != null) ? email.body.buffer.to_utf8() : null;
            
            this.fields = this.fields.set(Geary.Email.Field.BODY);
        }
    }
    
    private void unset_fields(Geary.Email.Field fields) {
        if ((fields & Geary.Email.Field.DATE) != 0) {
            date = null;
            date_time_t = -1;
            
            this.fields = this.fields.clear(Geary.Email.Field.DATE);
        }
        
        if ((fields & Geary.Email.Field.ORIGINATORS) != 0) {
            from = null;
            sender = null;
            reply_to = null;
            
            this.fields = this.fields.clear(Geary.Email.Field.ORIGINATORS);
        }
        
        if ((fields & Geary.Email.Field.RECEIVERS) != 0) {
            to = null;
            cc = null;
            bcc = null;
            
            this.fields = this.fields.clear(Geary.Email.Field.RECEIVERS);
        }
        
        if ((fields & Geary.Email.Field.REFERENCES) != 0) {
            message_id = null;
            in_reply_to = null;
            references = null;
            
            this.fields = this.fields.clear(Geary.Email.Field.REFERENCES);
        }
        
        if ((fields & Geary.Email.Field.SUBJECT) != 0) {
            subject = null;
            
            this.fields = this.fields.clear(Geary.Email.Field.SUBJECT);
        }
        
        if ((fields & Geary.Email.Field.HEADER) != 0) {
            header = null;
            
            this.fields = this.fields.clear(Geary.Email.Field.HEADER);
        }
        
        if ((fields & Geary.Email.Field.BODY) != 0) {
            body = null;
            
            this.fields = this.fields.clear(Geary.Email.Field.BODY);
        }
    }
}

