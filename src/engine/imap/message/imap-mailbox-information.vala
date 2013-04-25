/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.MailboxInformation : Object {
    public string name { get; private set; }
    public string? delim { get; private set; }
    public MailboxAttributes attrs { get; private set; }
    
    public MailboxInformation(string name, string? delim, MailboxAttributes attrs) {
        this.name = name;
        this.delim = delim;
        this.attrs = attrs;
    }
    
    /**
     * Will always return a list with at least one element in it.  If no delimiter is specified,
     * the name is returned as a single element.
     */
    public Gee.List<string> get_path() {
        Gee.List<string> path = new Gee.ArrayList<string>();
        
        if (!String.is_empty(delim)) {
            string[] split = name.split(delim);
            foreach (string str in split) {
                if (!String.is_empty(str))
                    path.add(str);
            }
        }
        
        if (path.size == 0)
            path.add(name);
        
        return path;
    }
    
    /**
     * If name is non-empty, will return a non-empty value which is the final folder name (i.e.
     * the parent components are stripped).  If no delimiter is specified, the name is returned.
     */
    public string get_basename() {
        if (String.is_empty(delim))
            return name;
        
        int index = name.last_index_of(delim);
        if (index < 0)
            return name;
        
        string basename = name.substring(index + 1);
        
        return !String.is_empty(basename) ? basename : name;
    }
    
    public static MailboxInformation decode(ServerData server_data) throws ImapError {
        StringParameter cmd = server_data.get_as_string(1);
        if (!cmd.equals_ci(ListCommand.NAME) && !cmd.equals_ci(ListCommand.XLIST_NAME))
            throw new ImapError.PARSE_ERROR("Not LIST or XLIST data: %s", server_data.to_string());
        
        ListParameter attrs = server_data.get_as_list(2);
        Gee.Collection<MailboxAttribute> attrlist = new Gee.ArrayList<MailboxAttribute>();
        foreach (Parameter attr in attrs.get_all()) {
            StringParameter? stringp = attr as StringParameter;
            if (stringp == null) {
                debug("Bad list attribute \"%s\": Attribute not a string value",
                    server_data.to_string());
                
                continue;
            }
            
            attrlist.add(new MailboxAttribute(stringp.value));
        }
        
        StringParameter? delim = server_data.get_as_nullable_string(3);
        StringParameter mailbox = server_data.get_as_string(4);
        
        // Set \Inbox to standard path
        MailboxInformation info;
        MailboxAttributes attributes = new MailboxAttributes(attrlist);
        if (Geary.Imap.MailboxAttribute.SPECIAL_FOLDER_INBOX in attributes) {
            return new MailboxInformation(Geary.Imap.Account.INBOX_NAME,
                (delim != null) ? delim.nullable_value : null, attributes);
        } else {
            return new MailboxInformation(mailbox.value,
                (delim != null) ? delim.nullable_value : null, attributes);
        }
    }
}

