/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.MessageRow : Geary.Sqlite.Row {
    public int64 id { get; set; default = INVALID_ID; }
    
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
    
    public string? subject { get; set; }
    
    public string? header { get; set; }
    
    public string? body { get; set; }
    
    public MessageRow(Table table) {
        base (table);
    }
    
    public MessageRow.from_email(MessageTable table, Geary.Email email) {
        base (table);
        
        date = (email.date != null) ? email.date.original : null;
        date_time_t = (email.date != null) ? email.date.as_time_t : -1;
        
        from = flatten_addresses(email.from);
        sender = flatten_addresses(email.sender);
        reply_to = flatten_addresses(email.reply_to);
        
        to = flatten_addresses(email.to);
        cc = flatten_addresses(email.cc);
        bcc = flatten_addresses(email.bcc);
        
        message_id = (email.message_id != null) ? email.message_id.value : null;
        in_reply_to = (email.in_reply_to != null) ? email.in_reply_to.value : null;
        
        subject = (email.subject != null) ? email.subject.value : null;
        
        header = (email.header != null) ? email.header.buffer.to_ascii_string() : null;
        
        body = (email.body != null) ? email.body.buffer.to_ascii_string() : null;
    }
    
    public MessageRow.from_query_result(Table table, Geary.Email.Field fields, SQLHeavy.QueryResult result)
        throws Error {
        base (table);
        
        id = fetch_int64_for(result, MessageTable.Column.ID);
        
        if ((fields & Geary.Email.Field.DATE) != 0) {
            date = fetch_string_for(result, MessageTable.Column.DATE_FIELD);
            date_time_t = (time_t) fetch_int64_for(result, MessageTable.Column.DATE_INT64);
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
        }
        
        if ((fields & Geary.Email.Field.SUBJECT) != 0)
            subject = fetch_string_for(result, MessageTable.Column.SUBJECT);
        
        if ((fields & Geary.Email.Field.HEADER) != 0)
            header = fetch_string_for(result, MessageTable.Column.HEADER);
        
        if ((fields & Geary.Email.Field.BODY) != 0)
            body = fetch_string_for(result, MessageTable.Column.BODY);
    }
    
    public Geary.Email to_email(int msg_num) throws Error {
        Geary.Email email = new Geary.Email(msg_num);
        
        email.date = (date != null) ? new RFC822.Date(date) : null;
        
        email.from = unflatten_addresses(from);
        email.sender = unflatten_addresses(sender);
        email.reply_to = unflatten_addresses(reply_to);
        
        email.to = unflatten_addresses(to);
        email.cc = unflatten_addresses(cc);
        email.bcc = unflatten_addresses(bcc);
        
        email.message_id = (message_id != null) ? new RFC822.MessageID(message_id) : null;
        email.in_reply_to = (in_reply_to != null) ? new RFC822.MessageID(in_reply_to) : null;
        
        email.subject = (subject != null) ? new RFC822.Subject(subject) : null;
        
        email.header = (header != null) ? new RFC822.Header(new Geary.Memory.StringBuffer(header))
            : null;
        
        email.body = (body != null) ? new RFC822.Text(new Geary.Memory.StringBuffer(body))
            : null;
        
        return email;
    }
    
    public string? flatten_addresses(RFC822.MailboxAddresses? addrs) {
        if (addrs == null)
            return null;
        
        switch (addrs.size) {
            case 0:
                return null;
            
            case 1:
                return addrs[0].get_full_address();
            
            default:
                StringBuilder builder = new StringBuilder();
                foreach (RFC822.MailboxAddress addr in addrs) {
                    if (!String.is_empty(builder.str))
                        builder.append(", ");
                    
                    builder.append(addr.get_full_address());
                }
                
                return builder.str;
        }
    }
    
    public RFC822.MailboxAddresses? unflatten_addresses(string? str) {
        if (str == null)
            return null;
        
        return null;
    }
}

